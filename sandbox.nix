# The nixpak sandbox that `nixulate` launches.
#
# `userConfig` is the optional ~/.config/nixulate.nix and `projectConfig` the
# optional ./nixulate.nix. Each is pulled in as a nixpak module, so either may
# be a plain attrset or a function taking { pkgs, lib, sloth, ... }.
# See OPTIONS.md.
{ userConfig ? null, projectConfig ? null }:

let
  nixpakSrc = builtins.fetchTarball {
    url = "https://github.com/nixpak/nixpak/archive/" +
      "333bd8c7ca0c014e61be1933b3c131c9dfa20218.tar.gz";
    sha256 = "07kilg6ips040zd5nsnv615b59d86l9akksprfmpbdq63sqa47ks";
  };

  # The host's nixpkgs, so the sandbox shares store paths with the system
  # instead of duplicating a second closure.
  pkgs = import <nixpkgs> { };

  mkNixPak = import "${nixpakSrc}/modules" {
    inherit (pkgs) lib;
    inherit pkgs;
  };

  sandbox = mkNixPak {
    config = { lib, ... }: {
      # imports, not mkMerge: it accepts a function as well as an attrset, so
      # nixulate.nix may take { pkgs, lib, sloth, ... }.
      imports = lib.optional (userConfig != null) userConfig
        ++ lib.optional (projectConfig != null) projectConfig;

      # A shell is the entrypoint so that `nixulate <cmd>` can run anything.
      app.package = pkgs.bashInteractive;

      bubblewrap = {
        # Resolved at launch, not at build, so one build serves every project.
        # The daemon socket lets `nix-shell` and friends build: the daemon owns
        # the store, so nothing inside needs to write to it.
        bind.rw = [
          "$NIXULATE_DIR"
          "/nix/var/nix/daemon-socket"
        ];

        # Without this Nix picks the local store and fails on the read-only
        # /nix/store bind instead of asking the daemon.
        env.NIX_REMOTE = "daemon";
        # /nix/store alone is not enough: the host PATH points into profile
        # symlink trees, which must be mounted for host tools to resolve.
        bind.ro = [
          "/etc"
          "/run/current-system"
          "/run/wrappers"
          "/nix/var/nix/profiles"
          "$HOME/.nix-profile"
          "$HOME/.local/state/nix/profile"
        ];

        network = true;
        dieWithParent = true;
        sockets = {
          wayland = true;
          x11 = true;
          pulse = true;
          pipewire = true;
        };
      };

      # Enabled for the proxy; every bus name stays closed until nixulate.nix
      # opens it explicitly.
      dbus.enable = true;
      dbus.policies = { };

      gpu.enable = true;
      etc.sslCertificates.enable = true;
      fonts.enable = true;
    };
  };
in sandbox.config.script
