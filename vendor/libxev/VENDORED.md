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

- Ordered writes survive transient backpressure (`src/backend/kqueue.zig`,
  `src/watcher/stream.zig`). The kqueue backend mapped EAGAIN from
  `write`, `pwrite`, `send` and `sendto` to `error.Unexpected`, and the
  ordered write queue then completed the head request with that error and
  moved on to the next buffer. A full pty during a large paste therefore cut
  one contiguous chunk out of the pasted text. kqueue now reports
  `error.WouldBlock`, and `queueWrite` keeps the head request and resubmits
  the same buffer on `WouldBlock`, exactly as it already did for partial
  writes. The `WouldBlock` switch goes through `anyerror` so it compiles for
  backends whose `WriteError` cannot contain it. Tests: `kqueue: write to a
  full pipe reports WouldBlock` and the two `queued writes` tests in
  `stream.zig`. Ported by behavior from manaflow-ai/ghostty `2f6ee7b3d` and
  `982a723ff`; that fork's older libxev already surfaced `WouldBlock`, so
  the kqueue mapping change is ours.
