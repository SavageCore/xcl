#!/usr/bin/env bash
# place-window.sh - find the XCL game window and pin its geometry.
# XCL titles its window "XCL - <game> | <fps> FPS" (class XCLGameWindow).
# Env: XCL_WIN_X Y W H, XCL_POLL, XCL_PLACE_TIMEOUT.
set -euo pipefail

: "${XCL_WIN_X:=640}"
: "${XCL_WIN_Y:=360}"
: "${XCL_WIN_W:=1280}"
: "${XCL_WIN_H:=720}"
: "${XCL_POLL:=2}"
: "${XCL_PLACE_TIMEOUT:=300}"

find_window() {
    local w
    for w in $(xdotool search --onlyvisible --name '^XCL' 2>/dev/null || true); do
        printf '%s\n' "$w"
        return 0
    done
    # Wine may keep the class but a different title
    xdotool search --onlyvisible --class 'XCLGameWindow' 2>/dev/null | head -1 || true
}

deadline=$(($(date +%s) + XCL_PLACE_TIMEOUT))
while [ "$(date +%s)" -lt "$deadline" ]; do
    w="$(find_window)"
    if [ -n "$w" ]; then
        for _ in 1 2 3; do
            xdotool windowactivate "$w" 2>/dev/null || true
            xdotool windowmove "$w" "$XCL_WIN_X" "$XCL_WIN_Y" 2>/dev/null || true
            xdotool windowsize "$w" "$XCL_WIN_W" "$XCL_WIN_H" 2>/dev/null || true
            sleep 1
            g="$(xdotool getwindowgeometry "$w" 2>/dev/null || true)"
            pos="$(printf '%s' "$g" | awk '/Position/ {print $2}')"
            geo="$(printf '%s' "$g" | awk '/Geometry/ {print $2}')"
            if [ "$geo" = "${XCL_WIN_W}x${XCL_WIN_H}" ] && [ "$pos" = "${XCL_WIN_X},${XCL_WIN_Y}" ]; then
                echo "place-window: $w at $pos ${geo} (verified)"
                exit 0
            fi
        done
        echo "place-window: WARNING: $w at $pos ${geo}, wanted ${XCL_WIN_X},${XCL_WIN_Y} ${XCL_WIN_W}x${XCL_WIN_H}" >&2
        exit 1
    fi
    sleep "$XCL_POLL"
done
echo "place-window: WARNING: no XCL window mapped within ${XCL_PLACE_TIMEOUT}s" >&2
exit 1
