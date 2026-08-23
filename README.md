# nixulate

Run a command in a [nixpak](https://github.com/nixpak/nixpak) sandbox rooted at the current directory.

```sh
cd ~/projects/scratch
nixulate npm install
```

`npm` runs with the project directory as the only writable path. The rest of your home is not there. `~/.ssh`, `~/.aws`, other projects: invisible.

Run with no arguments to get a shell inside the sandbox:

```sh
nixulate
```

## What is allowed by default

- **Write** — the current directory, and nothing else.
- **Read** — `/nix/store`, `/etc`, the system and user Nix profiles.
- **Network** — on.
- **GPU, Wayland, X11, audio** — on.
- **D-Bus** — proxy runs, but every bus name is closed.
- **Nix** — `nix-shell`, `nix-build` and `nix` work, through the host's Nix daemon.

Host tools resolve normally, so `git`, `node` and the rest of your `PATH` work without being declared.

This is a **loose** sandbox. It stops accidents and casual snooping. It is not built to hold a determined attacker, and enabling GUI or D-Bus access widens it further.

The Nix daemon socket is another such widening. Code in the sandbox can run builds and add paths to your real store. It cannot write to your files, and it cannot raise its own trust level, because the daemon decides that from `trusted-users`. To close it:

```nix
{ lib, ... }:
{
  bubblewrap.bind.rw = lib.mkForce [ "$NIXULATE_DIR" ];
}
```

## Install

Needs Nix with `nix-build`, `<nixpkgs>` on your `NIX_PATH`, and a Linux kernel with user namespaces.

The sandbox is built from your own nixpkgs, not a pinned copy. It therefore shares store paths with your system instead of downloading a second closure, and it changes when you update your channel.

```sh
git clone <this repo> ~/src/nixulate
ln -s ~/src/nixulate/nixulate ~/.local/bin/nixulate
```

Keep `nixulate` and `sandbox.nix` in the same directory: the script finds the Nix file next to itself.

## Per-project configuration

Drop a `nixulate.nix` in the project directory to extend the sandbox, or a `~/.config/nixulate.nix` to extend every sandbox:

```nix
{
  bubblewrap.bind.rw = [ "$HOME/.cache/pip" ];
  dbus.policies."org.freedesktop.Notifications" = "talk";
}
```

Both files are optional and both are nixpak modules, merged into the defaults. See [OPTIONS.md](OPTIONS.md).

## Speed

The first run builds the sandbox and may take a few minutes. After that every run costs about 0.9 seconds of Nix evaluation.

Nothing is cached outside the Nix store, and no garbage collection root is kept. If `nix-collect-garbage` removes the sandbox, the next run rebuilds it.

## How it works

1. `nixulate` looks for `~/.config/nixulate.nix` and `./nixulate.nix`.
2. It runs `nix-build sandbox.nix` passing whichever it found as `--arg userConfig` and `--arg projectConfig`. The result is a wrapper around `bwrap`.
3. It sets `NIXULATE_DIR` to the current directory and `execv`s the wrapper.

`sandbox.nix` binds the string `"$NIXULATE_DIR"`, which nixpak resolves at launch. So one build serves every project, and the sandbox is only rebuilt when either `nixulate.nix` changes.

Exit codes and signals pass through. One exception: Ctrl-C reports 255 instead of 130, because the interrupt also reaches `bwrap`, and nixpak's launcher turns any signal death into 255.

When there is a terminal, `nixulate` waits for the sandbox instead of replacing itself, and hands the terminal's foreground process group to it. This is needed because nixpak starts the sandbox in a new process group without claiming the terminal, and the sandbox runs in its own PID namespace where its own process group reads back as `0`. Without this, any program that reads the keyboard, such as `htop` or `less`, is stopped by `SIGTTIN` and shows nothing.
