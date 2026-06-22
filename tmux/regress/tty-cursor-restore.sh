#!/bin/sh

# The cursor must be visible after tmux switches back to the main screen.

PATH=/bin:/usr/bin
TERM=xterm

[ -z "$TEST_TMUX" ] && TEST_TMUX=$(readlink -f ../tmux)

TMP=$(mktemp)
SOCKET="cursor-restore-$$"
trap 'rm -f "$TMP"; "$TEST_TMUX" -L"$SOCKET" kill-server 2>/dev/null' 0 1 15

script -q -c "$TEST_TMUX -L$SOCKET -f/dev/null new-session 'exit 0'" \
    "$TMP" >/dev/null 2>&1 || exit 1

python3 - "$TMP" <<'PY'
import sys

data = open(sys.argv[1], "rb").read()
rmcup = data.rfind(b"\033[?1049l")
cnorm = data.find(b"\033[?25h", rmcup)

if rmcup == -1 or cnorm == -1:
    raise SystemExit(1)
PY
