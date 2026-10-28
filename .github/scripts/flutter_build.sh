#!/usr/bin/env bash
# Runs a `flutter build …` command. If it fails, the important error lines are
# shown as annotations on the run page (no need to dig through the full log).
set -uo pipefail
LOG=$(mktemp)
flutter "$@" 2>&1 | tee "$LOG"
code=${PIPESTATUS[0]}
if [ "$code" -ne 0 ]; then
  grep -E "What went wrong|error:|Error:|e: |FAILURE|Could not|Exception|requires|incompatible|failed" "$LOG" \
    | grep -v "^\s*$" | awk '!seen[$0]++' | head -25 | while IFS= read -r line; do
      echo "::error title=flutter $1 failed::${line:0:400}"
    done
  # The lines right after "What went wrong" carry the real reason.
  grep -A8 "What went wrong" "$LOG" | head -20 | while IFS= read -r line; do
    [ -n "${line// }" ] && echo "::error title=Gradle::${line:0:400}"
  done
fi
exit "$code"
