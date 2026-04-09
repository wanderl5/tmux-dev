# Repository Guidelines

## Project Structure & Module Organization
This repository is a thin wrapper around the `tmux/` source tree. Do most code changes inside `tmux/`, not at the repo root. Core C sources live in [`tmux/*.c`](./tmux) and shared declarations in `tmux.h`, `compat.h`, and `xmalloc.h`. Platform-specific code is split across `tmux/osdep-*.c`; portability shims live in `tmux/compat/`. Regression tests are shell scripts in `tmux/regress/`, fuzz inputs live in `tmux/fuzz/`, and auxiliary assets and scripts are under `tmux/tools/`, `tmux/logo/`, and `tmux/presentations/`. Repo-level helpers include `build.sh` and `CHANGES-feature.md`.

## Build, Test, and Development Commands
Use the repo helper for normal local builds:

- `./build.sh`: configure and compile `tmux/tmux`.
- `./build.sh -c`: clean prior outputs before rebuilding.
- `./build.sh -i`: install into `~/.local/bin`.
- `cd tmux && ./configure && make -j"$(nproc)"`: direct autotools build.
- `make -C tmux/regress`: run the shell regression suite.
- `cd tmux && nroff -mdoc tmux.1 | less`: preview the man page.

For debugging, run `cd tmux && ./tmux -vv` to emit server and client logs in the current directory.

## Coding Style & Naming Conventions
Follow the existing C style exactly: tabs for indentation, opening braces on the next line for functions, aligned wrapped arguments, and concise block comments. Keep filenames descriptive and consistent with nearby code, for example `cmd-*.c` for commands and `osdep-*.c` for platform hooks. Prefer small, local changes over new abstractions. Edit source files such as `Makefile.am` or `configure.ac`; avoid hand-editing generated files like `Makefile` unless regeneration is intentional.

## Testing Guidelines
Add or update a regression script in `tmux/regress/` for behavior changes. Name tests after the feature or bug being exercised, matching existing patterns like `new-session-size.sh` or `input-keys.sh`. Run the narrowest affected script first, then `make -C tmux/regress` before submitting. Include expected output files only when the test pattern already uses them.

## Commit & Pull Request Guidelines
Recent history favors short, imperative commit subjects; local feature work often uses prefixes such as `fix:`, `feat:`, and `chore:`. Keep each commit scoped to one behavior change. PRs should explain the user-visible impact, list verification steps, link any issue, and include terminal output or screenshots only when UI behavior changes. Do not commit generated binaries, object files, or local debug logs from `tmux/`.
