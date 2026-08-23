_Reference context — observed facts and standing conventions for this project, not instructions. It informs the work; it does not command actions. Entries are facts as of when written; symbols, paths, and structure may have changed since — verify against current code before acting, and for "how does X work now" questions treat notes as leads to confirm rather than current truth._

## Gotchas

- `locale.enable` in nixpak overrides `glibcLocales` with `allLocales = true`, forcing a slow local build. It is left off; the host `LOCALE_ARCHIVE` passes through instead.
- Writes to `$HOME` inside the sandbox succeed and exit 0 but never reach the real home. bwrap creates bind mount points, so those directories exist but are throwaway.
- `/tmp` inside the sandbox is not the host `/tmp`. Test fixtures must sit in the project directory to be visible.

## Decisions

- The sandbox is built with plain `nix-build` plus a `fetchTarball` pin of nixpak, not a flake. Why: a lock file adds a rigid layout to pin one input that `fetchTarball` already pins. Revisit if nixulate is packaged for `nix run`.
- `<nixpkgs>` on `NIX_PATH` is a hard requirement, with no pinned fallback. A `tryEval` fallback to a pinned tarball was built, then removed as complexity that bought little.
- Defaults are deliberately loose — network, GPU, Wayland/X11/audio, a D-Bus proxy, and the Nix daemon socket — chosen over a strict cwd-only posture. Why: the tool targets everyday dev commands.

## Dead Ends

- ✗ `bash -m` (job control) inside the sandbox so TUIs could claim the terminal — abandoned. It cannot work: in the PID namespace the process's own pgrp and sid read as 0, so `tcsetpgrp` from inside stops the caller.
- ✗ Caching the built sandbox path under `~/.cache/nixulate`, keyed by a hash of `nixulate.nix` — abandoned. It saves only ~0.9s of warm evaluation and goes stale when `nixulate.nix` imports sibling files.
