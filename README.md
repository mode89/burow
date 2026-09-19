# burow

Run a command in a Bubblewrap sandbox rooted at the current directory.

```sh
cd ~/projects/scratch
burow npm install
```

`npm` can write to the project directory. The rest of your home, including `~/.ssh`, `~/.aws`, and other projects, is replaced by an empty temporary filesystem.

Run with no arguments to start Bash inside the sandbox:

```sh
burow
```

## Default access

- **Write** — the current directory, a private `$HOME`, and a private `/tmp`. Only direct filesystem writes to the current directory persist through sandbox mounts; host services can make other persistent changes.
- **Read** — the Nix store and profiles, selected system files, and programs available through those mounts. The host `PATH` is inherited, but entries under hidden paths do not work.
- **Network** — the host network is shared.
- **Devices** — a private `/dev` is created and `/dev/kvm` is passed through.
- **D-Bus** — the user session bus is passed through without filtering.
- **Nix** — `nix-shell`, `nix-build`, and `nix` use the host Nix daemon.
- **Environment** — inherited, including any credentials stored in environment variables.

This is a convenience-first sandbox that limits accidental filesystem access. It is not a security boundary for hostile code. Network access, the unfiltered session bus, inherited environment variables, KVM, and the Nix daemon all expose host resources. In particular, the Nix daemon can add paths to the host store.

## Install

The defaults target NixOS and require:

- Nix with `nix-shell`, `<nixpkgs>` available through the legacy Nix path, and a multi-user daemon socket at `/nix/var/nix/daemon-socket`.
- A populated `USER` environment variable.
- A Linux kernel with user namespaces.
- `/dev/kvm` and an active user D-Bus socket at `/run/user/$UID/bus`.
- The NixOS paths bound by `bwrap-options`, including the certificate authority file, Nix configuration and profiles, `/run/current-system/sw`, `/usr/bin/env`, and `/bin/sh`.

Install the single executable:

```sh
git clone <this repo> ~/src/burow
ln -s ~/src/burow/burow ~/.local/bin/burow
```

The executable uses a `nix-shell` shebang to provide Babashka and Bubblewrap from the host's unpinned `<nixpkgs>`. The first run may download them; later runs reuse the Nix store. Babashka loads configuration and then replaces itself directly with Bubblewrap.

## Configuration

Configuration is Clojure evaluated by Babashka. It runs on the host before the sandbox starts, so use configuration only from projects you trust.

The following files are optional and load in order:

1. `$XDG_CONFIG_HOME/burow/config.clj`, or `~/.config/burow/config.clj` when `XDG_CONFIG_HOME` is unset.
2. `./.burow/config.clj` for shared project configuration.
3. `./.burow/config.local.clj` for local project configuration.
4. Every path given with `--config`, in the order given.

Old `config.py` files are ignored.

A config file declares its namespace, requires `burow`, and overrides a function. The override receives the previous implementation, which lets global, project, and local configuration compose.

Add a read-only host path:

```clojure
(ns burow.config
  (:require [burow :as burow]))

(burow/override burow/bwrap-options [previous]
  (into (previous)
        ["--ro-bind" "/opt/toolchain" "/opt/toolchain"]))
```

Disable network access. `--unshare-all` already creates a network namespace; this removes the later option that shares the host network:

```clojure
(ns burow.config
  (:require [burow :as burow]))

(burow/override burow/bwrap-options [previous]
  (remove #(= % "--share-net") (previous)))
```

An override can replace a function completely by not calling `previous`:

```clojure
(ns burow.config
  (:require [burow :as burow]))

(burow/override burow/bwrap-options [_previous]
  ["--unshare-all"
   "--die-with-parent"])
```

`override` accepts any function Var, including a Var from another namespace. The binding vector contains the previous function followed by the target function's arguments. Bubblewrap option order is significant, so inspect `bwrap-options` before replacing defaults or adding mounts that overlap them.

`bwrap-options-with-cwd` places `--chdir` and the current directory before the configured `bwrap-options`, so the directory appears near the start of the process arguments. It appends `--bind` for the current directory after those options to restore writable access after extension mounts. Separate mounts beneath that directory can still remain read-only. Replacing `bwrap-options` does not remove these directory options; override `bwrap-options-with-cwd` to change them.

Each config directory is added to the Babashka classpath before the config loads. A config can therefore move helper code into adjacent Clojure namespaces.

### Extra config files

`--config <path>` loads another Clojure config file after the three default files, so it can override them. Repeat the option to load several files. The path must exist; burow stops with an error if it does not. The file suffix does not affect how the file is evaluated.

```sh
burow --config ci/sandbox.clj npm test
```

burow reads only the options before the command, so the command keeps its own flags. For a program whose name starts with `-`, run it through `env`:

```sh
burow env -weird-name
```

## How it works

1. The `nix-shell` shebang starts Babashka with Babashka and Bubblewrap on `PATH`.
2. burow evaluates the global, project, and local Clojure configuration files that exist.
3. It gets Bubblewrap arguments from `bwrap-options-with-cwd`, which wraps the configured `bwrap-options` with the current-directory options.
4. Babashka replaces itself directly with Bubblewrap.
5. Bubblewrap requests isolation for every supported namespace, then shares the host network and mounts the allowed paths. User and cgroup namespace creation are best-effort Bubblewrap operations.
6. The requested command runs directly under Bubblewrap in the current directory.

Exit codes and signals pass through. Interactive programs use the calling terminal directly.
