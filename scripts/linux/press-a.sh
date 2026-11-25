#!/usr/bin/env bash
# press-a.sh - press pad A on the XCL window. XCL plays Enter or Space as pad A while
# its window has the focus (hle::kbm), so this is a plain Enter to the focused window.
# Env: XCL_APRESS (number of presses), XCL_APRESS_AT (seconds after the window maps,
# comma list, default 20,30,40,...), XCL_POLL, XCL_PRESS_KEY (default Return),
# XCL_PRESS_WAIT (window timeout, default 300s).
set -euo pipefail

: "${XCL_APRESS:=12}"
: "${XCL_APRESS_AT:=20,30,40,50,60,90,120,180,240,300,420,600}"
: "${XCL_POLL:=2}"
: "${XCL_PRESS_KEY:=Return}"
: "${XCL_PRESS_WAIT:=300}"
# held long enough for a title polling at 30 fps to see it through GetAsyncKeyState
: "${XCL_PRESS_HOLD:=0.3}"

find_window() {
    local w
    for w in $(xdotool search --onlyvisible --name '^XCL' 2>/dev/null || true); do
        printf '%s\n' "$w"
        return 0
    done
    xdotool search --onlyvisible --class 'XCLGameWindow' 2>/dev/null | head -1 || true
}

deadline=$(($(date +%s) + XCL_PRESS_WAIT))
w=""
while [ "$(date +%s)" -lt "$deadline" ]; do
    w="$(find_window)"
    [ -n "$w" ] && break
    sleep "$XCL_POLL"
done
if [ -z "$w" ]; then
    echo "press-a: WARNING: no XCL window, no presses sent" >&2
    exit 1
fi
echo "press-a: window $w, ${XCL_APRESS} X ${XCL_PRESS_KEY} at ${XCL_APRESS_AT}s"

start=$(date +%s)
sent=0
IFS=',' read -ra TIMES <<< "$XCL_APRESS_AT"
for t in "${TIMES[@]}"; do
    [ "$sent" -ge "$XCL_APRESS" ] && break
    now=$(( $(date +%s) - start ))
    wait=$(( t - now ))
    [ "$wait" -gt 0 ] && sleep "$wait"
    xdotool windowactivate "$w" 2>/dev/null || true
    xdotool keydown --clearmodifiers "$XCL_PRESS_KEY" 2>/dev/null || true
    sleep "$XCL_PRESS_HOLD"
    xdotool keyup "$XCL_PRESS_KEY" 2>/dev/null || true
    sent=$((sent + 1))
    echo "press-a: ${sent} at $(( $(date +%s) - start ))s"
done
