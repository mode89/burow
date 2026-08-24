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

- Python 3 and a populated `USER` environment variable.
- Nix with `nix-shell`, `<nixpkgs>` available through the legacy Nix path, and a multi-user daemon socket at `/nix/var/nix/daemon-socket`.
- A Linux kernel with user namespaces.
- `/dev/kvm` and an active user D-Bus socket at `/run/user/$UID/bus`.
- The NixOS paths bound by `bwrap_options()`, including the CA certificate, Nix configuration and profiles, `/run/current-system/sw`, `/usr/bin/env`, and `/bin/sh`.

Install the single executable:

```sh
git clone <this repo> ~/src/burow
ln -s ~/src/burow/burow ~/.local/bin/burow
```

Each invocation uses `nix-shell --packages bubblewrap` and then replaces itself with `bwrap`. The first run may download Bubblewrap; later runs reuse the Nix store.

## Configuration

Configuration is Python. It runs on the host before the sandbox starts, so use configuration only from projects you trust.

The following files are optional and load in order:

1. `$XDG_CONFIG_HOME/burow/config.py`, or `~/.config/burow/config.py` when `XDG_CONFIG_HOME` is unset.
2. `./.burow/config.py` for shared project configuration.
3. `./.burow/config.local.py` for local project configuration.

A config file imports `burow` and overrides a function. The override receives the previous implementation, which lets global, project, and local configuration compose.

Add a read-only host path:

```python
import burow


@burow.override
def bwrap_options(previous):
    return [
        *previous(),
        "--ro-bind", "/opt/toolchain", "/opt/toolchain",
    ]
```

Add packages to the outer `nix-shell`, making their programs available through `PATH` inside the sandbox:

```python
import burow


@burow.override
def nix_shell_packages(previous):
    return [*previous(), "nodejs_22"]
```

Disable network access. `--unshare-all` already creates a network namespace; this removes the later option that shares the host network:

```python
import burow


@burow.override
def bwrap_options(previous):
    return [option for option in previous() if option != "--share-net"]
```

Use the explicit decorator form when the wrapper has a different name:

```python
import burow


@burow.override(burow.bwrap_options)
def add_toolchain(previous):
    return [
        *previous(),
        "--ro-bind", "/opt/toolchain", "/opt/toolchain",
    ]
```

An override can replace a function completely by not calling `previous`. Bubblewrap option order is significant, so inspect `bwrap_options()` before replacing defaults or adding mounts that overlap them.

Config directories are added to Python's import path. A config can therefore move helper code into adjacent Python modules.

## How it works

1. `burow` imports the global, project, and local Python configuration files that exist.
2. It gets Bubblewrap arguments from `bwrap_options()` and packages from `nix_shell_packages()`.
3. It runs `nix-shell --packages ... --run ...` to provide Bubblewrap.
4. Bubblewrap requests isolation for every supported namespace, then shares the host network and mounts the allowed paths. User and cgroup namespace creation are best-effort Bubblewrap operations.
5. The requested command runs directly under Bubblewrap in the current directory.

Exit codes and signals pass through. Interactive programs use the calling terminal directly.
