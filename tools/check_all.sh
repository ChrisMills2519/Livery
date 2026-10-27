#!/usr/bin/env bash
# Headless check runner.
#
#   tools/check_all.sh                     every check
#   tools/check_all.sh --fast              skip the slow motion walkthrough
#   tools/check_all.sh --only check_save,check_touch
#   tools/check_all.sh --list              print the manifest and exit
#
# The manifest below is the single list of checks.  It used to live in the prose
# of agents.md, where it drifted: the document named ten of the tools that
# existed and nothing ran the rest.
#
# A cold clone has no .godot/, and every check loads a scene, so the import
# cache is built first.  Each check's own exit status is kept: a check that
# quits non-zero fails the run even if its output looks calm, and a timeout is
# reported as a timeout rather than a failure of the check.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

GODOT_BIN="${GODOT:-godot}"
FAST=0
LIST=0
ONLY=""
REPORT="artifacts/check-report.txt"

# name                      timeout  slow
# A slow entry is skipped by --fast: it walks every route in motion rather than
# asserting from one pose, and it is the two-minute one.
CHECKS=(
  "check_arena              180  0"
  "check_character_select   180  0"
  "check_character_swap     240  0"
  "check_care               180  0"
  "check_chihuahua_animations 180 0"
  "check_dog                240  0"
  "check_editor_load        300  0"
  "check_farmhouse          240  0"
  "check_feed               180  0"
  "check_fence_jump         180  0"
  "check_footprints         180  0"
  "check_groom              240  0"
  "check_horse_animations   180  0"
  "check_horse_state        240  0"
  "check_interior_cost      180  0"
  "check_jump_and_loop      240  0"
  "check_knockdown          180  0"
  "check_layout             180  0"
  "check_lead               180  0"
  "check_livery_logo        120  0"
  "check_mount              240  0"
  "check_muck               240  0"
  "check_player_models      180  0"
  "check_save               180  0"
  "check_scene_doors        180  0"
  "check_stable             180  0"
  "check_tack               240  0"
  "check_terrain_blend      180  0"
  "check_touch              180  0"
  "check_web_shell.py       120  0"
  "check_yard_props         180  0"
  "check_walkthrough        600  1"
)

# An entry ending in .py runs under python3 rather than Godot.  check_web_shell
# reads the built export, not the game, so it is a shell check; it skips itself
# on a checkout with no build/web-mobile, which is where CI runs it.

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --fast) FAST=1 ;;
    --list) LIST=1 ;;
    --only)
      shift
      ONLY="${1:-}"
      [ -n "$ONLY" ] || { echo "--only needs a name or a comma-separated list" >&2; exit 2; }
      ;;
    --only=*) ONLY="${1#--only=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$LIST" -eq 1 ]; then
  for entry in "${CHECKS[@]}"; do
    read -r name secs slow <<<"$entry"
    tag=""
    [ "$slow" -eq 1 ] && tag="  (slow)"
    printf '%-28s %3ss%s\n' "$name" "$secs" "$tag"
  done
  exit 0
fi

if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
  echo "no Godot binary: set GODOT=/path/to/godot" >&2
  exit 2
fi

# A check can only load a scene once the import cache exists.  Building it is
# the same command agents.md has always used for a cold checkout.
if [ ! -d .godot/imported ]; then
  echo "building the import cache (first run on this checkout)"
  if ! "$GODOT_BIN" --headless --editor --quit --path . >/dev/null 2>&1; then
    echo "the import step failed; run it by hand to see why:" >&2
    echo "  $GODOT_BIN --headless --editor --quit --path ." >&2
    exit 2
  fi
fi

# Checks that measure wall-clock motion or a heavy synchronous scene load.  On
# this 2.7 GB machine they have each failed once while the full suite ran them
# back to back and passed on their own: the assertions are untouched, and a
# genuine regression fails both attempts, so a failure is retried once before it
# counts.  Anything not listed here fails on the first try.
FLAKY=(check_character_select check_dog check_walkthrough)

is_flaky() {
  local name="$1"
  local entry
  for entry in "${FLAKY[@]}"; do
    [ "$entry" = "$name" ] && return 0
  done
  return 1
}

run_check() {
  local name="$1" secs="$2" out="$3"
  local cmd
  case "$name" in
    *.py) cmd=(python3 "tools/${name}") ;;
    *) cmd=("$GODOT_BIN" --headless --path . --script "res://tools/${name}.gd") ;;
  esac
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "${cmd[@]}" >"$out" 2>&1
  else
    "${cmd[@]}" >"$out" 2>&1
  fi
}

wanted() {
  local name="$1"
  [ -z "$ONLY" ] && return 0
  case ",$ONLY," in
    *",$name,"*) return 0 ;;
    *) return 1 ;;
  esac
}

mkdir -p "$(dirname "$REPORT")"
: >"$REPORT"

total=0
passed=0
failed=0
failed_names=()
started_all=$(date +%s)

for entry in "${CHECKS[@]}"; do
  read -r name secs slow <<<"$entry"
  wanted "$name" || continue
  if [ "$FAST" -eq 1 ] && [ "$slow" -eq 1 ]; then
    printf 'skip  %-28s (--fast)\n' "$name"
    echo "skip  $name  --fast" >>"$REPORT"
    continue
  fi

  total=$((total + 1))
  out="$(mktemp)"
  started=$(date +%s)
  run_check "$name" "$secs" "$out"
  status=$?
  retried=""
  if [ "$status" -ne 0 ] && is_flaky "$name"; then
    retried="  (retried)"
    printf 'retry %-28s first attempt failed\n' "$name"
    run_check "$name" "$secs" "$out"
    status=$?
  fi
  elapsed=$(( $(date +%s) - started ))

  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
    printf 'ok    %-28s %4ss%s\n' "$name" "$elapsed" "$retried"
    echo "ok    $name  ${elapsed}s${retried}" >>"$REPORT"
  else
    failed=$((failed + 1))
    failed_names+=("$name")
    if [ "$status" -eq 124 ]; then
      printf 'FAIL  %-28s %4ss  timed out after %ss\n' "$name" "$elapsed" "$secs"
      echo "FAIL  $name  ${elapsed}s  timeout ${secs}s" >>"$REPORT"
    else
      printf 'FAIL  %-28s %4ss  exit %s\n' "$name" "$elapsed" "$status"
      echo "FAIL  $name  ${elapsed}s  exit $status" >>"$REPORT"
    fi
    # Only the lines that explain the failure, not the whole run's log.
    grep -E 'FAIL|ERROR|SCRIPT ERROR|Parse Error' "$out" | head -12 | sed 's/^/        /'
    echo "        full output: rerun with" >>"$REPORT"
    case "$name" in
      *.py) echo "          python3 tools/${name}" >>"$REPORT" ;;
      *) echo "          \$GODOT --headless --path . --script res://tools/${name}.gd" >>"$REPORT" ;;
    esac
    grep -E 'FAIL|SCRIPT ERROR|Parse Error' "$out" | head -12 | sed 's/^/        /' >>"$REPORT"
  fi
  rm -f "$out"
done

total_time=$(( $(date +%s) - started_all ))
echo
if [ "$failed" -eq 0 ]; then
  echo "CHECK ALL: PASS (${passed}/${total} in ${total_time}s)"
  echo "CHECK ALL: PASS (${passed}/${total} in ${total_time}s)" >>"$REPORT"
  exit 0
fi
printf 'CHECK ALL: FAIL (%d of %d failed in %ds): %s\n' \
  "$failed" "$total" "$total_time" "${failed_names[*]}"
printf 'CHECK ALL: FAIL (%d of %d failed in %ds): %s\n' \
  "$failed" "$total" "$total_time" "${failed_names[*]}" >>"$REPORT"
echo "report: $REPORT"
exit 1
