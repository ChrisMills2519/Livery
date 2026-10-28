/* Ginger Games loading screen driver.
 *
 * Inlined into Godot's web shell by tools/export_web_mobile.py.  The exporter
 * also adds one line inside the shell's own onProgress callback:
 *
 *     window.gingerSplash && gingerSplash.set(current, total);
 *
 * so the screen follows the real byte counts of the 84 MiB pck and the 38 MiB
 * wasm rather than a timer.  Keep this file free of anything that can throw
 * before the hook is used: a thrown error here would leave the branded screen
 * frozen while the game loads perfectly well behind it.
 *
 * Elements are looked up when they are needed, not when this runs.  In the
 * shipped page the markup is above the script and either way works, but
 * tools/web_shell/preview.html injects the markup asynchronously, and a cached
 * null from parse time there is a screen that never moves -- which is exactly
 * the kind of failure this driver must not have.
 */
(function () {
	var cache = {};

	function element(id) {
		if (!cache[id]) {
			cache[id] = document.getElementById(id);
		}
		return cache[id];
	}

	var shown = -1;
	var revealed = false;

	function apply(fraction) {
		if (isNaN(fraction)) {
			return;
		}
		var value = Math.max(0, Math.min(1, fraction));
		var percent = Math.round(value * 100);
		var livery = element('ginger-livery');

		/* The horse arrives as the screen does, not on the first byte: the wait
		   for that first byte is the longest moment on a slow phone, and an empty
		   cream panel is not something to look at. */
		if (!revealed && livery) {
			revealed = true;
			livery.classList.add('is-in');
		}

		if (percent === shown) {
			return;
		}
		shown = percent;
		moved();

		var bar = element('ginger-bar');
		if (bar) {
			bar.style.setProperty('--ginger-progress', percent + '%');
		}
		placeBubble();
		var label = element('ginger-percent');
		if (label) {
			label.textContent = percent >= 100 ? 'READY' : 'LOADING ' + percent + '%';
		}
		if (percent >= 100) {
			document.body.classList.add('ginger-loaded');
		}
	}

	/* Stall detection: when the bar has not moved for a while, the puller strains
	   against it; when it moves again he heaves.  Only classes and text change, so
	   a stuck download can never freeze the screen. */
	var STALL_MS = 400;
	var lastMove = Date.now();
	var straining = false;
	var heaveTimer = null;
	var bubbleTimer = null;
	var lines = ['hnnngh\u2026', 'come on!', 'one more pull\u2026'];
	var lineIndex = 0;

	function setBubble(text) {
		var bubble = element('ginger-bubble');
		if (bubble) {
			bubble.textContent = text;
			placeBubble();
		}
	}

	/* Ahead of the puller is where the bubble belongs, until he reaches the end of
	   the track: then it would hang off the edge of the screen, which on a phone
	   is 41 px of `one more pull...` cut off.  The side is chosen from the measured
	   boxes rather than from a progress threshold, so a tablet, with room to
	   spare, keeps it ahead.  Guarded throughout: a loading screen may not throw. */
	function placeBubble() {
		var bubble = element('ginger-bubble');
		var bar = element('ginger-bar');
		if (!bubble || !bar) {
			return;
		}
		var width = bubble.offsetWidth;
		if (!width) {
			return;
		}
		var box = bar.getBoundingClientRect();
		var edge = box.left + box.width * (Math.max(0, shown) / 100);
		var roomAhead = window.innerWidth - (edge + 60);
		var roomBehind = edge - 8;
		bar.classList.toggle('ginger-bubble-back', roomAhead < width && roomBehind > roomAhead);
	}
	window.addEventListener('resize', placeBubble);

	function moved() {
		lastMove = Date.now();
		if (!straining) {
			return;
		}
		straining = false;
		clearInterval(bubbleTimer);
		var bar = element('ginger-bar');
		if (bar) {
			bar.classList.remove('ginger-strain');
			bar.classList.add('ginger-heave');
		}
		setBubble('yes!');
		clearTimeout(heaveTimer);
		heaveTimer = setTimeout(function () {
			var current = element('ginger-bar');
			if (current) {
				current.classList.remove('ginger-heave');
			}
			setBubble('');
		}, 700);
	}

	function startStrain() {
		straining = true;
		var bar = element('ginger-bar');
		if (bar) {
			bar.classList.add('ginger-strain');
		}
		lineIndex = 0;
		setBubble(lines[0]);
		clearInterval(bubbleTimer);
		bubbleTimer = setInterval(function () {
			lineIndex = (lineIndex + 1) % lines.length;
			setBubble(lines[lineIndex]);
		}, 1400);
	}

	setInterval(function () {
		if (!straining && !document.body.classList.contains('ginger-loaded') && Date.now() - lastMove > STALL_MS) {
			startStrain();
		}
	}, 100);

	window.gingerSplash = {
		set: function (current, total) {
			if (total > 0) {
				apply(current / total);
			}
		},
	};

	/* Draw the empty bar and the puller at its left end before the first byte
	   arrives, so the screen is never a bar with no driver. */
	apply(0);
})();
