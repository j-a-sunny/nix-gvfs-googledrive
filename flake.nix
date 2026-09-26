{
  description = "Restores Google Drive support to gvfs and gnome-online-accounts on NixOS";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:

    let
      # Bumped automatically by .github/workflows/update-gvfs-fork.yml
      gvfsRev = "89a2e179fb547887614bc3977bc735e986461163";
      gvfsHash = "sha256-pfIO4lAPK2lzx2Q35wMH+5rBSQGklYON++sovfu629g=";

      overlay =
        final: prev:

        {
          gnome = prev.gnome.overrideScope (
            gfinal: gprev:

            {
              gvfs =
                (prev.gnome.gvfs.override {
                  gnomeSupport = true;
                }).overrideAttrs
                  (oldAttrs: {

                    src = final.fetchurl {
                      url = "https://gitlab.gnome.org/fluhus/gvfs/-/archive/${gvfsRev}/gvfs-${gvfsRev}.tar.gz";
                      hash = gvfsHash;
                    };

                    # daemon/meson.build google backend requires json-glib
                    buildInputs = oldAttrs.buildInputs ++ [
                      final.json-glib
                    ];

                    mesonFlags = oldAttrs.mesonFlags ++ [
                      "-Dgoogle=true"
                    ];
                  });
            }
          );

          # gnome-online-accounts is top-level in current nixpkgs
          gnome-online-accounts = prev.gnome-online-accounts.overrideAttrs (oldAttrs: {
            mesonFlags = oldAttrs.mesonFlags ++ [
              "-Dgoogle_files=true"
            ];
          });

        };

      nixosModule =
        {
          config,
          lib,
          ...
        }:

        {
          options.services.gvfsGoogleDrive.enable = lib.mkEnableOption "gvfs + gnome-online-accounts Google Drive support";

          config = lib.mkIf config.services.gvfsGoogleDrive.enable {

            nixpkgs.overlays = [
              overlay
            ];

            services.gvfs.enable = true;

            services.gnome.gnome-online-accounts.enable = true;

          };
        };

      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      packagesForSystem =
        system:

        let
          pkgs = import nixpkgs {
            inherit system;

            overlays = [
              overlay
            ];

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

      checks = forAllSystems (
        system:

        self.packages.${system}
      );

    };
}
