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

assert_match() {
	label=$1
	pattern=$2
	actual=$3

	if printf '%s\n' "$actual" | grep -Eq "$pattern"; then
		if [ -n "$VERBOSE" ]; then
			echo "[PASS] $label"
		fi
	else
		echo "[FAIL] $label"
		echo "  expected pattern: $pattern"
		echo "  actual:           $actual"
		exit_status=1
	fi
}

vertical=$($TMUX list-keys -N | grep -- 'Split window vertically')
assert_match "vertical split binding" \
	'^C-b _[[:space:]]+Split window vertically$' \
	"$vertical"

horizontal=$($TMUX list-keys -N | grep -- 'Split window horizontally')
assert_match "horizontal split binding" \
	'^C-b \|[[:space:]]+Split window horizontally$' \
	"$horizontal"

$TMUX kill-server 2>/dev/null
exit $exit_status
