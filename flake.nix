{
  description = "Restores Google Drive support to gvfs and gnome-online-accounts on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      # Bumped automatically by .github/workflows/update-gvfs-fork.yml
      gvfsRev = "89a2e179fb547887614bc3977bc735e986461163";
      gvfsHash = "sha256-pfIO4lAPK2lzx2Q35wMH+5rBSQGklYON++sovfu629g=";

      overlay = final: prev: {
        gnome = prev.gnome.overrideScope (
          gfinal: gprev: {
            gvfs =
              (gprev.gvfs.override {
                gnomeSupport = true; # required: gvfs's google backend asserts goa is enabled
              }).overrideAttrs
                (oldAttrs: {
                  src = final.fetchurl {
                    url = "https://gitlab.gnome.org/fluhus/gvfs/-/archive/${gvfsRev}/gvfs-${gvfsRev}.tar.gz";
                    hash = gvfsHash;
                  };
                  # daemon/meson.build's google block links gvfsd-google against
                  # json-glib directly; gnome-online-accounts' own json-glib
                  # buildInput isn't propagated, so it must be declared here too.
                  buildInputs = oldAttrs.buildInputs ++ [ final.json-glib ];
                  mesonFlags = oldAttrs.mesonFlags ++ [ "-Dgoogle=true" ];
                });
          }
        );

        # gnome-online-accounts is NOT part of the gnome.* scope in current
        # nixpkgs (pkgs/desktops/gnome/default.nix only keeps gvfs there now,
        # everything else moved to top-level) - override it directly here, not
        # inside gnome.overrideScope, or eval fails with:
        #   error: attribute 'gnome-online-accounts' missing
        # Same upstream source nixpkgs already fetches, just with the
        # (upstream, off-by-default) flag flipped on - no custom src needed.
        gnome-online-accounts = prev.gnome-online-accounts.overrideAttrs (oldAttrs: {
          mesonFlags = oldAttrs.mesonFlags ++ [ "-Dgoogle_files=true" ];
        });

        # services.gvfs.package defaults to pkgs.gnome.gvfs, which the override
        # above already reaches. But gnome.overrideScope only rewires
        # references *inside* the gnome scope - if gvfs is also installed
        # directly from the top-level pkgs set anywhere (environment.systemPackages,
        # home-manager, etc.), that separate attribute needs aliasing too.
        gvfs = final.gnome.gvfs;
      };

      nixosModule = { config, lib, pkgs, ... }: {
        options.services.gvfsGoogleDrive.enable = lib.mkEnableOption
          "gvfs + gnome-online-accounts Google Drive support";

        config = lib.mkIf config.services.gvfsGoogleDrive.enable {
          nixpkgs.overlays = [ overlay ];
          services.gvfs.enable = true;
          services.gnome.gnome-online-accounts.enable = true;
        };
      };

      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      packagesForSystem = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
            config.allowUnfree = true;
          };
        in
        {
          gvfs-googledrive = pkgs.gnome.gvfs;
          gnome-online-accounts-googledrive = pkgs.gnome-online-accounts;
        };
    in
    {
      overlays.default = overlay;
      nixosModules.default = nixosModule;

      packages = forAllSystems packagesForSystem;

      # `nix flake check` / CI sanity build target
      checks = forAllSystems (system: self.packages.${system});
    };
}
