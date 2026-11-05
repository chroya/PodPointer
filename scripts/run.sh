#!/bin/bash
# Launch PodPointer and follow its log.
#
#   scripts/run.sh                    normal use
#   scripts/run.sh --probe            only log sensor data (never moves the cursor)
#   scripts/run.sh --tap-debug        also log rejected tap candidates
#   scripts/run.sh --gain 1800 --invert-x …   see README for all options
#
# While running, type a note and press Enter to stamp it into the log
# (e.g. "closed lid"); type q + Enter to quit the app.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[ -d build/PodPointer.app ] || scripts/build.sh

SUPPORT="$HOME/Library/Application Support/PodPointer"
LOG="$HOME/Library/Logs/PodPointer.log"
mkdir -p "$SUPPORT"

pkill -x PodPointer 2>/dev/null && sleep 0.3
: > "$LOG"
# LaunchServices sometimes drops --args; the app falls back to this file.
echo "$*" > "$SUPPORT/launch-args"
open -n build/PodPointer.app --args "$@"

echo "Log: $LOG   (type a note + Enter to mark the log, q + Enter to quit)"
tail -n +1 -F "$LOG" &
TAIL=$!
trap 'kill $TAIL 2>/dev/null' EXIT
while IFS= read -r line; do
  [ "$line" = "q" ] && { pkill -x PodPointer; break; }
  echo "[$(date +%H:%M:%S.000)] ---- note: ${line:-(empty)} ----" >> "$LOG"
done
