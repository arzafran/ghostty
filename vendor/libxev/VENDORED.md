# Vendored libxev

Source: mitchellh/libxev at `819ffa180ca20e31c7eded74e2e1aceb1eab557f`, the
same tarball upstream Ghostty fetches
(`https://deps.files.ghostty.org/libxev-819ffa180ca20e31c7eded74e2e1aceb1eab557f.tar.gz`,
package hash `libxev-0.0.0-86vtc8QQFACz0sVc7U-VDiDIgH-XfBuEY5JpABLjHNpn`).

Imported files: `build.zig`, `build.zig.zon`, `LICENSE`, `README.md`,
`docs/`, `examples/`, `include/` and `src/`. The website, Nix files and CI
configuration are left out; `build.zig` does not reference them.

The fork vendors libxev so it can carry the local patches listed below.
When upstream Ghostty bumps libxev, re-import the new tarball here and
re-apply each patch.

## Local patches

None yet.
