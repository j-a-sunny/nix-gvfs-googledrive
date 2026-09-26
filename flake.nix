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
        # Overriding directly at the top level since gvfs is no longer isolated to the gnome scope
        gvfs = (prev.gvfs.override {
          gnomeSupport = true; # required: gvfs's google backend asserts goa is enabled
        }).overrideAttrs (oldAttrs: {
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

        gnome-online-accounts = prev.gnome-online-accounts.overrideAttrs (oldAttrs: {
          mesonFlags = oldAttrs.mesonFlags ++ [ "-Dgoogle_files=true" ];
        });
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
          # Updated to target the top-level pkgs.gvfs
          gvfs-googledrive = pkgs.gvfs;
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