#!/bin/sh

# default-terminal should fall back if the configured terminal is missing

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null

TMP=$(mktemp)
OUT=$(mktemp)
SCRIPT=$(mktemp)
trap "rm -f $TMP $OUT $SCRIPT" 0 1 15

cat <<EOF >$SCRIPT
printf '%s\n' "\$TERM" >$OUT
EOF

cat <<EOF >$TMP
set -g default-terminal "tmux-missing"
new -d /bin/sh $SCRIPT
EOF

$TMUX -f$TMP start || exit 1
sleep 1
[ "$(cat $OUT)" = "screen" ] || exit 1

$TMUX kill-server 2>/dev/null

exit 0
