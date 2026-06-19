#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -f/dev/null -Ltest"
$TMUX kill-server 2>/dev/null
TMP=$(mktemp)
trap 'rm -f "$TMP"' 0 1 15

$TMUX new -d -x40 -y10 "printf hello; cat" || exit 1
sleep 1

$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
$TMUX send-keys -X begin-selection
$TMUX send-keys -X cursor-right
$TMUX send-keys -X copy-selection
printf 'show-messages\n' | $TMUX -C attach >"$TMP"
grep -q 'message: copied' "$TMP" || exit 1

$TMUX send-keys -X copy-selection
printf 'show-messages\n' | $TMUX -C attach >"$TMP"
grep -q 'message: copy failed' "$TMP" || exit 1

$TMUX kill-server 2>/dev/null
exit 0
