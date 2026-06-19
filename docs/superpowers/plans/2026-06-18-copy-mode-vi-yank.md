# Copy Mode Vi Yank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add core Vim visual selection and yank behavior with explicit copy success or failure feedback.

**Architecture:** Keep selection and buffer handling in `window-copy.c`, but return a boolean result from copy helpers so command handlers can display accurate status messages. Define Vim-compatible bindings and a one-key transient yank table in `key-bindings.c`.

**Tech Stack:** C99, tmux command/key tables, POSIX shell regression tests.

---

### Task 1: Copy Result Feedback

**Files:**
- Modify: `tmux/window-copy.c`
- Test: `tmux/regress/copy-feedback.sh`

- [ ] **Step 1: Run the failing feedback test**

Run:

```sh
cd tmux/regress && sh copy-feedback.sh
```

Expected: FAIL because no `copied` or `copy failed` status message exists.

- [ ] **Step 2: Make copy helpers return success**

Change `window_copy_copy_pipe`, `window_copy_copy_selection`, and
`window_copy_append_selection` from `void` to `int`. Return `1` only after a
nonempty selection is obtained and stored, otherwise return `0`.

- [ ] **Step 3: Display the result from command handlers**

Add a helper equivalent to:

```c
static void
window_copy_copy_feedback(struct client *c, int copied)
{
	status_message_set(c, -1, 1, 0, "%s",
	    copied ? "copied" : "copy failed");
}
```

Call it once from each selection, line, end-of-line, append, and copy-pipe
command handler after the copy attempt.

- [ ] **Step 4: Verify feedback behavior**

Run:

```sh
cd tmux/regress && VERBOSE=1 sh copy-feedback.sh
```

Expected: PASS for both successful and unsuccessful copies.

### Task 2: Core Vim Selection and Yank Bindings

**Files:**
- Modify: `tmux/key-bindings.c`
- Create: `tmux/regress/copy-mode-vi-keys.sh`

- [ ] **Step 1: Add failing binding assertions**

Create a test that starts tmux with `/dev/null`, then checks these bindings:

```text
C-v -> begin-selection; rectangle-on
V   -> select-line
v   -> rectangle-off; begin-selection
y   -> if selection_present, copy-pipe-and-cancel; otherwise switch to copy-mode-vi-yank
copy-mode-vi-yank y -> copy-pipe-line-and-cancel
```

- [ ] **Step 2: Run the binding test**

Run:

```sh
cd tmux/regress && sh copy-mode-vi-keys.sh
```

Expected: FAIL because the current `v` and `C-v` toggle rectangles and no `y`
binding exists.

- [ ] **Step 3: Replace the Vim bindings**

Use existing tmux commands:

```tmux
bind -Tcopy-mode-vi C-v { send -X begin-selection; send -X rectangle-on }
bind -Tcopy-mode-vi V { send -X select-line }
bind -Tcopy-mode-vi v { send -X rectangle-off; send -X begin-selection }
bind -Tcopy-mode-vi y { if -F '#{selection_present}' { send -X copy-pipe-and-cancel } { switch-client -Tcopy-mode-vi-yank } }
bind -Tcopy-mode-vi-yank y { send -X copy-pipe-line-and-cancel }
```

An unmatched second key is swallowed by tmux's existing temporary key-table
fallback and returns the client to its normal copy-mode table.

- [ ] **Step 4: Verify bindings and copy behavior**

Run:

```sh
cd tmux/regress && VERBOSE=1 sh copy-mode-vi-keys.sh
sh copy-mode-test-vi.sh
```

Expected: all commands exit with status `0`.

### Task 3: Build and Regression Verification

**Files:**
- Modify: `tmux/key-bindings.c`
- Modify: `tmux/window-copy.c`
- Test: `tmux/regress/copy-feedback.sh`
- Test: `tmux/regress/copy-mode-vi-keys.sh`
- Test: `tmux/regress/prefix-hint.sh`

- [ ] **Step 1: Build tmux**

Run:

```sh
./build.sh
```

Expected: build succeeds and reports tmux `3.5a`.

- [ ] **Step 2: Run focused regressions**

Run:

```sh
cd tmux/regress
sh copy-feedback.sh
sh copy-mode-vi-keys.sh
sh copy-mode-test-vi.sh
sh copy-mode-test-emacs.sh
sh prefix-hint.sh
```

Expected: every script exits with status `0`.

- [ ] **Step 3: Check the patch**

Run:

```sh
git diff --check
git status --short
```

Expected: no whitespace errors and only intended source, test, and plan changes.
