#!/bin/sh

PATH=/bin:/usr/bin
TERM=screen

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)
TMUX="$TEST_TMUX -Ltest"
$TMUX kill-server 2>/dev/null
sleep 1
$TMUX -f/dev/null new -d || exit 1

exit_status=0

assert_eq() {
	label=$1
	expected=$2
	actual=$3

	if [ "$expected" = "$actual" ]; then
		if [ -n "$VERBOSE" ]; then
			echo "[PASS] $label"
		fi
	else
		echo "[FAIL] $label"
		echo "  expected: $expected"
		echo "  actual:   $actual"
		exit_status=1
	fi
}

binding=$($TMUX list-keys | grep 'M-n')
assert_eq "M-n binding" \
	'bind-key    -T root         M-n                    command-prompt -p "new session name" { new-session -s -- "%%" }' \
	"$binding"

hint=$($TMUX display-message -p '#{client_prefix_hint}')
assert_eq "prefix hint text" \
	"Prefix active: c new-session, s sessions, _ split-vertical, | split-horizontal, d detach, ? keys" \
	"$hint"

$TMUX kill-server 2>/dev/null
exit $exit_status
