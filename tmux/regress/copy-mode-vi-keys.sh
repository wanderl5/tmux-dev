#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -f/dev/null -Ltest"
$TMUX kill-server 2>/dev/null
TMP=$(mktemp)
trap 'rm -f "$TMP"' 0 1 15
$TMUX new -d -x40 -y10 "printf 'hello world'; cat" || exit 1
sleep 1

assert_binding_contains() {
	table=$1
	key=$2
	expected=$3
	binding=$($TMUX list-keys -T "$table" "$key" 2>/dev/null) || exit 1
	printf '%s\n' "$binding" | grep -Fq "$expected" || {
		echo "binding $table $key does not contain: $expected"
		echo "actual: $binding"
		exit 1
	}
}

assert_binding_contains copy-mode-vi C-v 'begin-selection'
assert_binding_contains copy-mode-vi C-v 'rectangle-on'
assert_binding_contains copy-mode-vi V 'select-line'
assert_binding_contains copy-mode-vi v 'rectangle-off'
assert_binding_contains copy-mode-vi v 'begin-selection'
assert_binding_contains copy-mode-vi y 'selection_present'
assert_binding_contains copy-mode-vi y 'copy-pipe-and-cancel'
assert_binding_contains copy-mode-vi y 'copy-mode-vi-yank'
assert_binding_contains copy-mode-vi-yank y 'copy-pipe-line-and-cancel'

$TMUX set-window-option -g mode-keys vi
$TMUX copy-mode
$TMUX send-keys -X history-top
$TMUX send-keys -X start-of-line
printf 'send-keys -K y\nsend-keys -K y\nshow-buffer\n' |
	$TMUX -C attach >"$TMP"
grep -q '^%paste-buffer-changed buffer0$' "$TMP" || exit 1

$TMUX kill-server 2>/dev/null
exit 0
