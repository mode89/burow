# `nixulate.nix` options

`nixulate.nix` is a [nixpak](https://github.com/nixpak/nixpak) module. It is merged into the defaults in `sandbox.nix`, so you only write what you want to change.

Two files are read, both optional:

- `~/.config/nixulate.nix` — applies to every project. Honours `XDG_CONFIG_HOME`.
- `./nixulate.nix` — applies to this project only.

When both exist they are merged together with the defaults. Neither wins by rank: lists join, and a clash on a single value is an error unless one side uses `lib.mkForce`. A project can therefore override your user config, but it must say so.

## Two forms

A plain attrset, when you need nothing from Nix:

```nix
{
  bubblewrap.bind.ro = [ "/opt/toolchain" ];
}
```

A function, when you need packages or helpers:

```nix
{ pkgs, lib, sloth, ... }:
{
  bubblewrap.env.PATH = "${pkgs.nodejs_22}/bin";
}
```

## Overriding a default

Lists and attrsets merge, so `bind.ro` adds to the default list. To *replace* or *disable* a default, use `lib.mkForce`:

```nix
{ lib, ... }:
{
  bubblewrap.network = lib.mkForce false;
}
```

Without `mkForce` you get a conflict error.

## Paths

A path starting with `$` is resolved when the sandbox starts, not when it is built:

```nix
{
  bubblewrap.bind.rw = [ "$HOME/.cache/pip" ];
}
```

`sloth` is the long form of the same thing, and handles more cases:

```nix
{ sloth, ... }:
{
  bubblewrap.bind.rw = [ (sloth.concat' sloth.homeDir "/.cache/pip") ];
}
```

`sloth.homeDir`, `sloth.runtimeDir`, `sloth.env "VAR"`, `sloth.envOr "VAR" "fallback"`, `sloth.concat [ ... ]`, `sloth.concat' a b`, `sloth.mkdir dir`, `sloth.instanceId`.

To bind a host path to a different path inside, use a two-element list:

```nix
{
  bubblewrap.bind.ro = [ [ "/etc/hosts" "/etc/hosts.orig" ] ];
}
```

Binds are "try" binds: a missing source path is skipped, not an error.

---

# Reference

## Filesystem

- **`bubblewrap.bind.rw`** — list of path, default `[ "$NIXULATE_DIR" "/nix/var/nix/daemon-socket" ]`. Writable paths. The daemon socket is what makes `nix-shell` work; `lib.mkForce` the list to drop it.
- **`bubblewrap.bind.ro`** — list of path, default see `sandbox.nix`. Read-only paths.
- **`bubblewrap.bind.dev`** — list of path, default `[]`. Device paths (`/dev/...`).
- **`bubblewrap.tmpfs`** — list of path, default `[]`. Empty writable scratch, discarded on exit.
- **`bubblewrap.bindEntireStore`** — bool, default `true`. Mount all of `/nix/store`. Off means only the closure.
- **`bubblewrap.extraStorePaths`** — list of package, default `[]`. Extra store paths when `bindEntireStore` is off.

```nix
{
  bubblewrap.tmpfs = [ "/tmp" ];
  bubblewrap.bind.dev = [ "/dev/ttyUSB0" ];
}
```

## Environment

- **`bubblewrap.env`** — attrs of str, default `{ NIX_REMOTE = "daemon"; }`. Variables to set inside.

Setting the same variable in both `~/.config/nixulate.nix` and `./nixulate.nix` **concatenates** the two values instead of reporting a clash, because nixpak's env type has no merge rule. `FOO = "a"` and `FOO = "b"` give `FOO=ba`. Use `lib.mkForce` when you mean to replace.
- **`bubblewrap.clearEnv`** — bool, default `false`. Drop every inherited variable first.

```nix
{ pkgs, ... }:
{
  bubblewrap.clearEnv = true;
  bubblewrap.env = {
    PATH = "${pkgs.nodejs_22}/bin:${pkgs.coreutils}/bin";
    HOME = "/tmp";
  };
}
```

Note: `clearEnv = true` also drops `NIXULATE_DIR`, which `nixulate` needs to enter your project directory. Set it back yourself if you use this.

## Network

- **`bubblewrap.network`** — bool, default `true`. Share the host network.
- **`pasta.enable`** — bool, default `false`. Use a user-mode network stack instead.

```nix
{ lib, ... }:
{
  bubblewrap.network = lib.mkForce false;
}
```

## Namespaces and process

- **`bubblewrap.shareIpc`** — bool, default `false`. Share the host IPC namespace.
- **`bubblewrap.newSession`** — bool, default `false`. New terminal session. Blocks TTY injection, but breaks interactive use.
- **`bubblewrap.dieWithParent`** — bool, default `true`. Kill children when `nixulate` exits.
- **`bubblewrap.apivfs.proc`** — bool, default `true`. Mount a private `/proc`.
- **`bubblewrap.apivfs.dev`** — bool, default `true`. Mount a private `/dev`.

## Desktop sockets

- **`bubblewrap.sockets.wayland`** — default `true`.
- **`bubblewrap.sockets.x11`** — default `true`.
- **`bubblewrap.sockets.pulse`** — default `true`.
- **`bubblewrap.sockets.pipewire`** — default `true`.

```nix
{ lib, ... }:
{
  bubblewrap.sockets.x11 = lib.mkForce false;
}
```

## D-Bus

`dbus.enable` is `true`, but `dbus.policies` is **empty**: every bus name is closed until you open it. Values are `"see"`, `"talk"` or `"own"`.

```nix
{
  dbus.policies = {
    "org.freedesktop.Notifications" = "talk";
    "org.freedesktop.portal.*" = "talk";
  };
}
```

Finer control:

```nix
{
  dbus.rules.call."org.freedesktop.portal.Desktop" = [ "org.freedesktop.portal.FileChooser.*" ];
}
```

Opening a broad name such as `"*" = "talk"` can let a process escape the sandbox. Open only what you need.

## GPU

- **`gpu.enable`** — bool, default `true`.
- **`gpu.provider`** — `"raw"`, `"nixos"` or `"bundle"`, default `"nixos"`.
- **`gpu.bundlePackage`** — package, default `pkgs.mesa`.

`nixos` mounts the host's drivers. Use `bundle` on a non-NixOS host.

## Certificates, fonts, time zone

```nix
{ pkgs, ... }:
{
  etc.sslCertificates.enable = true;   # default true
  fonts.enable = true;                 # default true
  fonts.fonts = [ pkgs.jetbrains-mono ];

  timeZone = {
    enable = true;
    provider = "bundle";               # or "host"
    zone = "Europe/Berlin";
  };
}
```

## Anything else

The full module set is in the nixpak source. To browse it:

```sh
nix repl
:l <nixpak-source>/modules
```
