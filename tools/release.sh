#!/usr/bin/env bash
# One-command release: export the web build, publish it to R2, assert the host.
#
#   tools/release.sh                 export, upload, check
#   tools/release.sh --dry-run       export, then report wire sizes; no upload
#   tools/release.sh --skip-export   publish build/web-mobile exactly as it is
#
# Credentials and the target host come from .env beside the repo root (see
# tools/deploy_r2.py); nothing is passed by hand and nothing is echoed.
set -euo pipefail
cd "$(dirname "$0")/.."

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  grep '^# ' "$0" | cut -c3-
  exit 0
fi

dry=0
export_build=1
for arg in "$@"; do
  case "$arg" in
    --dry-run) dry=1 ;;
    --skip-export) export_build=0 ;;
    *) echo "release: unknown option $arg (try --help)" >&2; exit 2 ;;
  esac
done

if [ "$export_build" = 1 ]; then
  echo "== export =="
  python3 tools/export_web_mobile.py
fi

if [ "$dry" = 1 ]; then
  echo "== deploy (dry run: nothing is uploaded) =="
  python3 tools/deploy_r2.py --dry-run
  exit 0
fi

echo "== deploy =="
python3 tools/deploy_r2.py

echo "== check =="
set +e
python3 tools/deploy_r2.py --check
status=$?
set -e
if [ "$status" != 0 ]; then
  echo "release: the host check reported failures (exit $status)." >&2
  echo "         On the r2.dev address the expected one is / -> 404, which the" >&2
  echo "         custom domain plus a Redirect Rule fixes." >&2
fi
exit "$status"
