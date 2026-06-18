# Copy Mode Vi Yank Design

## Scope

Add the core Vim selection and yank behavior to tmux copy mode:

- `v` starts character-wise selection.
- `V` starts line-wise selection.
- `C-v` starts rectangular selection.
- `y` copies an active selection and exits copy mode.
- `yy` copies the current line and exits copy mode.

Operator combinations such as `yw`, `y$`, and `yiw` are out of scope.

## Key Handling

The existing copy-mode engine remains responsible for selection and copying.
The default vi bindings will compose its existing commands:

- `v`: `rectangle-off`, then `begin-selection`.
- `V`: `select-line`.
- `C-v`: `begin-selection`, then `rectangle-on`.
- `y` with an active selection: `copy-pipe-and-cancel`.
- `y` without an active selection: enter a transient yank key table where a
  second `y` runs `copy-pipe-line-and-cancel`.

Any unsupported key in the transient table returns to copy mode without
copying.

## Copy Feedback

Copy commands report `copied` when they obtain nonempty selected content and
store it in the tmux paste buffer. They report `copy failed` when no content
can be obtained. An asynchronous external `copy-command` exit status is not
part of this synchronous result.

## Testing

Regression coverage will verify:

- Successful and unsuccessful copy feedback in the server message log.
- The `v`, `V`, and `C-v` command bindings.
- Visual-selection `y` behavior.
- The transient `yy` line-copy binding.
- Existing copy-mode buffer tests continue to pass.
