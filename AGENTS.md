# Working on nixulate

`nixulate <cmd>` runs `<cmd>` in a [nixpak](https://github.com/nixpak/nixpak) sandbox where only the current directory is writable. See README.md for behaviour and OPTIONS.md for the `nixulate.nix` schema.

Four files, no build step, no test framework:

- `nixulate` — Python. Builds the sandbox, hands it the terminal, execs it.
- `sandbox.nix` — the nixpak module holding every default.
- `OPTIONS.md`, `README.md` — the only docs.

Policy belongs in `sandbox.nix`. `nixulate` should stay limited to building, terminal handover and exec.

## Verify

There are no unit tests. Run these after any change.

Sandbox builds:

```sh
nix-build sandbox.nix --no-out-link
```

Every Nix example in the docs builds:

```sh
python3 -c "
import re, pathlib
b = sum((re.findall(r'\`\`\`nix\n(.*?)\`\`\`', pathlib.Path(f).read_text(), re.S) for f in ('OPTIONS.md', 'README.md')), [])
for i, x in enumerate(b): pathlib.Path(f'/tmp/ex{i}.nix').write_text(x)
print(len(b), 'examples')"
for f in /tmp/ex*.nix; do nix-build sandbox.nix --arg projectConfig "import $f" --no-out-link >/dev/null || echo "FAIL $f"; done
```

Isolation and exit codes:

```sh
./nixulate sh -c 'touch ./p && echo ok && rm p'   # writable
./nixulate cat "$HOME/.ssh/id_rsa"                # must fail
./nixulate curl -sI --max-time 8 https://example.com
./nixulate false; echo $?                         # 1
./nixulate sh -c 'kill -TERM $$'; echo $?         # 143
./nixulate sh -c 'nix-shell -p hello --run hello'
```

Terminal behaviour cannot be checked from a pipe. Drive it through a pty with `pty.fork`, set the window size with `TIOCSWINSZ`, then confirm `htop` renders, redraws after an arrow key, and quits on `q`. A pty without a size reports `stty size` as `0 0` and every TUI stays blank, which looks like a bug in `nixulate` but is not.

## Things that will mislead you

**Bind paths starting with `$` resolve at launch, not at build.** nixpak's `coerceToEnv` turns `"$NIXULATE_DIR"` into a runtime lookup. That is why one build serves every project directory, and why the sandbox is only rebuilt when `nixulate.nix` changes. Do not add per-directory build inputs.

**`/nix/store` alone does not make host tools work.** The host `PATH` points into profile symlink trees such as `/run/current-system/sw/bin`. Those are bound separately in `sandbox.nix`. Removing them breaks every command.

**The sandbox cannot claim the terminal itself.** nixpak's launcher starts bwrap with `Setpgid: true` and never calls `tcsetpgrp`, and `--unshare-pid` is hardcoded, so inside the sandbox `getpgrp()` and `getsid()` both read `0`. Only `nixulate` knows the real ids, so it must do the handover. Without it any program that reads the keyboard is stopped by `SIGTTIN` and prints nothing, while `echo` still works, because background groups may write but not read.

**Find the sandbox group across all launcher threads.** `/proc/PID/task/TID/children` lists one thread's children. The launcher is a Go program and starts bwrap from an arbitrary thread, so read `/proc/PID/task/*/children`. Reading only the main thread finds nothing and the handover silently does not happen.

**Ctrl-C reports 255, not 130.** The interrupt reaches bwrap too, and the launcher does `os.Exit(exiterr.ExitCode())`, which is `-1` for a signal death. Upstream, not fixable here.

**`NIX_REMOTE=daemon` is required for `nix-shell`.** Binding the daemon socket is not enough. Without the variable Nix picks the local store and fails writing a lock file into the read-only `/nix/store`.

**`bubblewrap.env` values concatenate on clash instead of erroring.** nixpak's env type is a custom `mkOptionType` with no merge rule, so the module system falls back to `mergeDefaultOption`, which joins strings. Two configs both setting `FOO` silently produce the two values stuck together. Other option types conflict properly.

**nixpak option names are not guessable.** It is `fonts.enable`, not `gui.fonts.enable`. Check the real module before adding an option:

```sh
nix repl
:l <nixpak-source>/modules
```

**Do not pin nixpkgs.** `sandbox.nix` uses the host `<nixpkgs>` on purpose. A pinned nixpkgs shared zero store paths with the system and duplicated a 118 MB closure. Only nixpak is pinned, because it is not on `NIX_PATH`.

## Documentation style

No Markdown tables; use lists. Do not hard-wrap lines. Every Nix example must build.

---

**Memory — read first.** Read `MEMORY.md` at the start of each session, before your first response — it records facts about this project, its conventions, landmines, dead ends, and decision rationale you can't recover from the code. Skipping it risks repeating solved mistakes.
