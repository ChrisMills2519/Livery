extends Node

## Web play-session analytics for the family dashboard.
##
## One session covers one visit to the game.  It starts when the player presses
## Ride out on the character-select screen and ends when the menu loads again,
## the tab is hidden/closed, or a new run replaces it.  GDScript owns the
## session id, the UTC start timestamp, the 30 s heartbeat and the ended flag;
## the JavaScript bridge only carries the three payloads and owns the pagehide
## listeners that must outlive the engine.
##
## Nothing here is awaited, every failure is swallowed, and every entry point
## is a no-op outside the web export, so analytics can never touch gameplay.

const GAME_ID := "livery"
const ENDPOINT := "https://qmywqscmpduitgjqrfyb.supabase.co/functions/v1/log_session"
## Supabase's publishable anon key.  It is already embedded in the other four
## public game pages, so it belongs in the client.
const ANON_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFteXdxc2NtcGR1aXRnanFyZnliIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTI5Mjk3ODUsImV4cCI6MjEwODUwNTc4NX0.lUg_sLn4uWB4JXe997Xa08VYdvhjHkbda0iaFzuV0Zk"
const HEARTBEAT_SECONDS := 30
const ALPHABET := "0123456789abcdefghijklmnopqrstuvwxyz"

## The transport lives in JavaScript on purpose: Godot's HTTPRequest has no
## keepalive mode, and a closed tab cancels an in-flight request, so the end
## event has to go out through the browser's own fetch.  The listeners are
## installed once at boot because pagehide must outlive the engine.
const BRIDGE_JS := """
(function () {
  try {
    if (window.__liveryAnalytics) { return; }
    var endpoint = "__ENDPOINT__";
    var key = "__ANON_KEY__";
    var session = null;

    function post(body, keepalive) {
      try {
        fetch(endpoint, {
          method: "POST",
          headers: {
            "content-type": "application/json",
            "authorization": "Bearer " + key
          },
          body: JSON.stringify(body),
          keepalive: !!keepalive
        }).catch(function () {});
      } catch (error) {}
    }

    function finish(status) {
      try {
        if (session === null || session.ended) { return; }
        session.ended = true;
        var now = Date.now();
        post({
          event: "end",
          id: session.id,
          game_id: "__GAME_ID__",
          started_at: session.startedAt,
          duration_seconds: Math.max(0, Math.round((now - session.startedMs) / 1000)),
          ended_at: new Date(now).toISOString(),
          status: String(status || "quit")
        }, true);
      } catch (error) {}
    }

    window.addEventListener("pagehide", function () { finish("quit"); });
    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState === "hidden") { finish("quit"); }
    });

    window.__liveryAnalytics = {
      start: function (id, startedAt, startedMs) {
        try {
          finish("restart");
          session = { id: id, startedAt: startedAt, startedMs: startedMs, ended: false };
          post({ event: "start", id: id, game_id: "__GAME_ID__", started_at: startedAt }, false);
        } catch (error) {}
      },
      heartbeat: function (durationSeconds) {
        try {
          if (session === null || session.ended) { return; }
          post({
            event: "heartbeat",
            id: session.id,
            game_id: "__GAME_ID__",
            started_at: session.startedAt,
            duration_seconds: durationSeconds
          }, false);
        } catch (error) {}
      },
      end: function (status) { finish(status); }
    };
  } catch (error) {}
})();
"""

var _active := false
var _ended := true
var _session_id := ""
var _started_at := ""
var _started_ms := 0
var _next_heartbeat_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_eval(BRIDGE_JS
		.replace("__ENDPOINT__", ENDPOINT)
		.replace("__ANON_KEY__", ANON_KEY)
		.replace("__GAME_ID__", GAME_ID))


## The heartbeat is gated on the wall clock, not on a Timer: Godot clamps the
## frame delta (about 0.13 s here), so a delta-driven Timer needs hundreds of
## frames to reach 30 s and a slow tablet would silently miss every heartbeat.
func _process(_delta: float) -> void:
	if not _active or _ended:
		return
	var now_ms := _now_ms()
	if now_ms < _next_heartbeat_ms:
		return
	_next_heartbeat_ms = now_ms + HEARTBEAT_SECONDS * 1000
	_eval("window.__liveryAnalytics && window.__liveryAnalytics.heartbeat(%d);" % _elapsed_seconds())


## Starts a session.  A live session is ended first, so restarting a run can
## never leave two live rows behind.
func start() -> void:
	if not OS.has_feature("web"):
		return
	if _active and not _ended:
		end("restart")
	var now_ms := _now_ms()
	_session_id = "s_" + _base36(now_ms) + _random_suffix()
	_started_at = _utc_iso8601(now_ms)
	_started_ms = now_ms
	_next_heartbeat_ms = now_ms + HEARTBEAT_SECONDS * 1000
	_active = true
	_ended = false
	_eval("window.__liveryAnalytics && window.__liveryAnalytics.start(%s, %s, %d);" % [
		JSON.stringify(_session_id),
		JSON.stringify(_started_at),
		now_ms,
	])


## Ends the live session exactly once.  The JavaScript side carries the same
## guard because pagehide can end the session without GDScript running.
func end(status := "quit") -> void:
	if not OS.has_feature("web"):
		return
	if not _active or _ended:
		return
	_active = false
	_ended = true
	_eval("window.__liveryAnalytics && window.__liveryAnalytics.end(%s);" % JSON.stringify(String(status)))


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _elapsed_seconds() -> int:
	return maxi(0, int(round(float(_now_ms() - _started_ms) / 1000.0)))


func _random_suffix() -> String:
	var suffix := ""
	for i in range(8):
		suffix += ALPHABET[randi() % ALPHABET.length()]
	return suffix


func _base36(value: int) -> String:
	var remaining := value
	var encoded := ""
	while remaining > 0:
		encoded = ALPHABET[remaining % 36] + encoded
		remaining /= 36
	return encoded if not encoded.is_empty() else "0"


func _utc_iso8601(unix_ms: int) -> String:
	var seconds := int(floor(float(unix_ms) / 1000.0))
	var millis := unix_ms - seconds * 1000
	return "%s.%03dZ" % [Time.get_datetime_string_from_unix_time(seconds, false), millis]


func _eval(code: String) -> void:
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval(code, true)
