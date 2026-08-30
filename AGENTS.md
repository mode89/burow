# Working on burow

`burow <cmd>` runs `<cmd>` directly under `bwrap`, with the current directory as the only persistent writable filesystem bind. A `nix-shell` shebang provides Babashka and Bubblewrap at launch time.

The project has one executable and no build step or test framework:

- `burow` — Clojure evaluated by Babashka. Loads configuration, defines the sandbox policy, and replaces itself with the sandboxed command.
- `README.md` — user documentation and configuration examples.
- `AGENTS.md` — maintainer instructions.
- `MEMORY.md` — curated context that is not recoverable cheaply from the other files.

Sandbox policy belongs in `bwrap-options`. Keep configuration loading in `load-config` and process launch in `main`. Babashka and Bubblewrap are fixed packages in the `nix-shell` shebang.

## Configuration model

Configuration is trusted Clojure evaluated on the host before the sandbox starts. Files load in this order:

1. `$XDG_CONFIG_HOME/burow/config.clj`, defaulting to `~/.config/burow/config.clj`.
2. `./.burow/config.clj`.
3. `./.burow/config.local.clj`.
4. Every path passed with `--config`, in the order given.

Old `config.py` files are ignored. `main` reads options only until the first argument that is not an option; the rest is the command.

Each file declares a namespace, requires `[burow :as burow]`, and can use `burow/override` to wrap a function. The binding vector receives the previous implementation first, followed by the target function's arguments. Later files wrap earlier files. A wrapper may call the previous function to extend it or omit that call to replace it. Config directories are added to the Babashka classpath so adjacent helper namespaces can be required.

## Verify

There are no unit tests. Run these after a change.

Clojure and documentation syntax:

```sh
./burow --bogus true; test $? -eq 1
nix-shell -p babashka --run "bb -e '(let [text (slurp \"README.md\") blocks (map second (re-seq (re-pattern \"(?s)\`\`\`clojure\\n(.*?)\`\`\`\") text))] (doseq [block blocks] (read-string (str \"(\" block \"\\n)\"))))'"
```

Configuration order and override chaining:

```sh
repo=$PWD
tmp=$(mktemp -d -p "$repo")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/xdg/burow" "$tmp/project/.burow"
write_config() {
    printf '(ns config.%s (:require [burow :as burow]))\n(burow/override burow/bwrap-options [previous]\n  (into (previous) ["--setenv" "BUROW_CONFIG_ORDER" "%s"]))\n' "$2" "$2" > "$1"
}
write_config "$tmp/xdg/burow/config.clj" global
write_config "$tmp/project/.burow/config.clj" project
write_config "$tmp/project/.burow/config.local.clj" local
(cd "$tmp/project" && XDG_CONFIG_HOME="$tmp/xdg" "$repo/burow" sh -c 'test "$BUROW_CONFIG_ORDER" = local')

write_config "$tmp/extra.clj" extra
(cd "$tmp/project" && XDG_CONFIG_HOME="$tmp/xdg" "$repo/burow" --config "$tmp/extra.clj" sh -c 'test "$BUROW_CONFIG_ORDER" = extra')
./burow --config /nonexistent.clj true; echo $?   # 1, config not found
./burow --bogus true; echo $?                     # 1, unknown option
```

Isolation, networking, nested Nix, and exit status:

```sh
home_marker=$(mktemp "$HOME/.burow-test.XXXXXX")
tmp_marker=$(mktemp /tmp/burow-test.XXXXXX)
trap 'rm -f "$home_marker" "$tmp_marker"' EXIT
./burow sh -c 'test ! -e "$1" && test ! -e "$2"' sh "$home_marker" "$tmp_marker"
./burow sh -c 'touch ./p && echo ok && rm p'
./burow curl -sI --max-time 8 https://example.com
./burow sh -c 'nix-shell -p hello --run hello'
./burow false; echo $?                         # 1
./burow sh -c 'kill -TERM $$'; echo $?         # 143
```

Run an interactive command such as `./burow htop` from a real terminal after changes to process launch or namespace options. A pipe is not a terminal and cannot verify keyboard handling.

## Things that will mislead you

**Configuration is outside the security boundary.** Config files are evaluated before `bwrap` starts and can run arbitrary host code. Treat project configuration as trusted code.

**The environment is inherited.** Files in the host home are hidden, but credentials already stored in environment variables remain visible unless configuration changes the Bubblewrap environment.

**The default host paths are strict.** Launch fails if a source used by `--bind`, `--ro-bind`, or `--dev-bind` does not exist. The defaults assume NixOS paths, `/dev/kvm`, and an active user D-Bus socket.

**`/nix/store` alone does not make host tools work.** The inherited `PATH` can include profile symlink trees such as `/run/current-system/sw/bin`, so the default policy binds `/run/current-system/sw` and Nix profiles too.

**`NIX_REMOTE=daemon` is required for nested Nix commands.** Binding the daemon socket is not enough. Without the variable, Nix selects the local store and fails when it tries to write into the read-only `/nix/store`.

**D-Bus is not filtered.** The user bus is bound directly into the sandbox. This and the Nix daemon make the defaults unsuitable as a security boundary for hostile code.

**`$HOME` and `/tmp` are disposable mounts.** Writes there can succeed but disappear when the command exits. Put test fixtures in the project directory if a later sandbox command must see them.

**Bubblewrap option order matters.** Configuration normally appends options to the previous vector. Check how a later mount or namespace option interacts with the defaults before assuming it replaces one.

## Documentation style

No Markdown tables; do not hard-wrap lines. Every Clojure example must parse.

---

**Memory — read first.** Read `MEMORY.md` at the start of each session, before your first response. It records facts about this project, its conventions, landmines, dead ends, and decision rationale that cannot be recovered cheaply from the code.
