# Working on nixulate

`nixulate <cmd>` runs `<cmd>` directly under `bwrap`, with the current directory as the only persistent writable filesystem bind. `nix-shell` provides Bubblewrap at launch time.

The project has one executable and no build step or test framework:

- `nixulate` — Python. Loads configuration, defines the sandbox policy, asks `nix-shell` for runtime packages, and replaces itself with the sandboxed command.
- `README.md` — user documentation and configuration examples.
- `AGENTS.md` — maintainer instructions.
- `MEMORY.md` — curated context that is not recoverable cheaply from the other files.

Sandbox policy belongs in `bwrap_options()`. Packages needed to start the sandbox belong in `nix_shell_packages()`. Keep configuration loading in `load_config()` and process launch in `main()`.

## Configuration model

Configuration is trusted Python executed on the host before the sandbox starts. Files load in this order:

1. `$XDG_CONFIG_HOME/nixulate/config.py`, defaulting to `~/.config/nixulate/config.py`.
2. `./.nixulate/config.py`.
3. `./.nixulate/config.local.py`.

Each file can `import nixulate` and use `@nixulate.override` to wrap a function. The wrapper receives the previous implementation as its first argument, so later files wrap earlier files. A wrapper may call the previous function to extend it or omit that call to replace it.

## Verify

There are no unit tests. Run these after a change.

Python and documentation syntax:

```sh
python3 -m py_compile nixulate
python3 - <<'PY'
import re
from pathlib import Path
for block in re.findall(r'```python\n(.*?)```', Path('README.md').read_text(), re.S):
    compile(block, 'README.md', 'exec')
PY
```

Configuration order and override chaining:

```sh
repo=$PWD
tmp=$(mktemp -d -p "$repo")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/xdg/nixulate" "$tmp/project/.nixulate"
write_config() {
    printf 'import nixulate\n@nixulate.override\ndef bwrap_options(previous):\n    return [*previous(), "--setenv", "NIXULATE_CONFIG_ORDER", "%s"]\n' "$2" > "$1"
}
write_config "$tmp/xdg/nixulate/config.py" global
write_config "$tmp/project/.nixulate/config.py" project
write_config "$tmp/project/.nixulate/config.local.py" local
(cd "$tmp/project" && XDG_CONFIG_HOME="$tmp/xdg" "$repo/nixulate" sh -c 'test "$NIXULATE_CONFIG_ORDER" = local')
```

Isolation, networking, nested Nix, and exit status:

```sh
home_marker=$(mktemp "$HOME/.nixulate-test.XXXXXX")
tmp_marker=$(mktemp /tmp/nixulate-test.XXXXXX)
trap 'rm -f "$home_marker" "$tmp_marker"' EXIT
./nixulate sh -c 'test ! -e "$1" && test ! -e "$2"' sh "$home_marker" "$tmp_marker"
./nixulate sh -c 'touch ./p && echo ok && rm p'
./nixulate curl -sI --max-time 8 https://example.com
./nixulate sh -c 'nix-shell -p hello --run hello'
./nixulate false; echo $?                         # 1
./nixulate sh -c 'kill -TERM $$'; echo $?         # 143
```

Run an interactive command such as `./nixulate htop` from a real terminal after changes to process launch or namespace options. A pipe is not a terminal and cannot verify keyboard handling.

## Things that will mislead you

**Configuration is outside the security boundary.** Config files are imported before `bwrap` starts and can run arbitrary host code. Treat project configuration as trusted code.

**The environment is inherited.** Files in the host home are hidden, but credentials already stored in environment variables remain visible unless configuration changes the environment.

**The default host paths are strict.** Launch fails if a source used by `--bind`, `--ro-bind`, or `--dev-bind` does not exist. The defaults assume NixOS paths, `/dev/kvm`, and an active user D-Bus socket.

**`/nix/store` alone does not make host tools work.** The inherited `PATH` can include profile symlink trees such as `/run/current-system/sw/bin`, so the default policy binds `/run/current-system/sw` and Nix profiles too.

**`NIX_REMOTE=daemon` is required for nested Nix commands.** Binding the daemon socket is not enough. Without the variable, Nix selects the local store and fails when it tries to write into the read-only `/nix/store`.

**D-Bus is not filtered.** The user bus is bound directly into the sandbox. This and the Nix daemon make the defaults unsuitable as a security boundary for hostile code.

**`$HOME` and `/tmp` are disposable mounts.** Writes there can succeed but disappear when the command exits. Put test fixtures in the project directory if a later sandbox command must see them.

**Bubblewrap option order matters.** Configuration normally appends options to the previous list. Check how a later mount or namespace option interacts with the defaults before assuming it replaces one.

## Documentation style

No Markdown tables; use lists. Do not hard-wrap lines. Every Python example must compile.

---

**Memory — read first.** Read `MEMORY.md` at the start of each session, before your first response — it records facts about this project, its conventions, landmines, dead ends, and decision rationale you can't recover from the code. Skipping it risks repeating solved mistakes.
