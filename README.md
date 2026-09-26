# gvfs-googledrive (NixOS)

Restores Google Drive support to `gvfs` and the "Files" toggle in GNOME
Online Accounts on NixOS, via a flake overlay + NixOS module. This is the
NixOS equivalent of the Arch AUR `gvfs-googledrive` /
`gnome-online-accounts-googledrive` packages in this same repo, based on
[Amit Lavon (`fluhus`)](https://gitlab.gnome.org/fluhus)'s forks/patches.

The `gvfsRev`/`gvfsHash` pin in `flake.nix` is checked against
[`gitlab.gnome.org/fluhus/gvfs`](https://gitlab.gnome.org/fluhus/gvfs) daily
by [`.github/workflows/update-gvfs-fork.yml`](.github/workflows/update-gvfs-fork.yml)
and auto-committed when upstream moves, after a build sanity check passes.

## What this actually does

There are two separate pieces, and you need both:

1. **`gvfs`** — provides the `gvfsd-google` mount backend (FUSE-mounted
   Drive folder, `google-drive://` locations). Built from
   `gitlab.gnome.org/fluhus/gvfs` with `-Dgoogle=true` (requires
   `gnomeSupport = true` / `-Dgoa=true`).
2. **`gnome-online-accounts`** — decides whether the **"Files" toggle even
   appears** in Settings → Online Accounts for a Google account. This is a
   separate deprecation from gvfs's own
   ([upstream MR !384](https://gitlab.gnome.org/GNOME/gnome-online-accounts/-/merge_requests/384)
   turned it off by default). No fork source needed here — it's plain
   upstream `gnome-online-accounts` with `-Dgoogle_files=true` added, an
   option that already exists upstream, just off by default.

Nautilus doesn't talk to Google Drive directly — it discovers Drive as a
location purely by asking GOA (via D-Bus) which accounts have the Files
feature enabled. If you only patch `gvfs`, the backend works but nothing
ever offers to mount it.

## Usage

### Option A — NixOS module (recommended)

```nix
{
  inputs.gvfs-googledrive.url = "github:j-a-sunny/gvfs-googledrive"; # or path:./gvfs-googledrive if vendored
}
```

```nix
# in a module included in your nixosSystem's `modules`:
{ inputs, ... }: {
  imports = [ inputs.gvfs-googledrive.nixosModules.default ];
  services.gvfsGoogleDrive.enable = true;
}
```

That applies the overlay and sets `services.gvfs.enable` and
`services.gnome.gnome-online-accounts.enable` for you.

### Option B — overlay only

```nix
nixpkgs.overlays = [ inputs.gvfs-googledrive.overlays.default ];
services.gvfs.enable = true;
services.gnome.gnome-online-accounts.enable = true;
```

Use this if you want overlay-only control (e.g. you already manage those
two `services.*.enable` options elsewhere, or want to compose this overlay
with others manually).

## After rebuilding

1. **Fully log out and back in** (or reboot). `goa-daemon` and
   `gnome-control-center` hold the old libraries in memory — closing
   Settings isn't enough.
2. In Settings → Online Accounts, **remove and re-add** the Google account
   so it re-registers with the patched daemon.
3. Check the **Files toggle in Settings itself** first. If present there
   but Nautilus still doesn't show the Drive location, check
   `journalctl --user -u gvfs-daemon` and `journalctl --user -b | grep -i goa`.

## Pitfalls already hit (so you don't have to)

1. `.override { gnomeSupport = true; googleSupport = true; }` →
   `error: ... called with unexpected argument 'googleSupport'`. There is
   no `googleSupport` argument — only `gnomeSupport`. The actual toggle is
   the `-Dgoogle=true` mesonFlag.
2. Missing `json-glib` in `buildInputs` → `gvfsd-google` fails to link,
   since `daemon/meson.build` uses
   `dependency('json-glib-1.0', required: false)`, which silently resolves
   to "not found" if it isn't declared, then fails when used to build the
   target. GOA's own `json-glib` dependency isn't propagated to things
   linking against it.
3. Overriding `gnome-online-accounts` *inside* `gnome.overrideScope` →
   `error: attribute 'gnome-online-accounts' missing`. Current nixpkgs
   keeps only `gvfs` in the `gnome.*` scope
   (`pkgs/desktops/gnome/default.nix`); everything else moved to
   top-level. Override it as a plain top-level attribute in the same
   overlay instead.
4. Installing `gvfs`/`gnome-online-accounts` via
   `environment.systemPackages = with pkgs; [ ... ]` bypasses the
   `gnome.*` scope entirely, since that's a separate top-level attribute
   path `gnome.overrideScope` never touches — hence the `gvfs = final.gnome.gvfs;`
   alias line at the bottom of the overlay.

## Updating the pin manually

```console
$ git -C /path/to/fluhus-gvfs-clone log -1 --format=%H
$ nix store prefetch-file --hash-type sha256 --json \
    "https://gitlab.gnome.org/fluhus/gvfs/-/archive/<REV>/gvfs-<REV>.tar.gz"
```

Paste the rev into `gvfsRev` and the `.hash` field into `gvfsHash` in
`flake.nix`. (The GitHub Action does this automatically — this is only
needed for manual/offline updates.)

## References

- Fork source: <https://gitlab.gnome.org/fluhus/gvfs>
- Background: <https://discourse.gnome.org/t/google-drive-in-gnome-50/34417>,
  <https://discussion.fedoraproject.org/t/call-for-testers-restoring-google-drive-integration-in-gnome/189348>
- GOA feature-removal commit: [MR !384](https://gitlab.gnome.org/GNOME/gnome-online-accounts/-/merge_requests/384)
- Arch reference packages (confirmed no source patches involved, just build
  flags): AUR `gvfs-googledrive`, AUR `gnome-online-accounts-googledrive`
