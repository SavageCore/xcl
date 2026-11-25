# AGENTS.md - this checkout on Linux/Proton

Clone-specific notes for `xcl` on this machine. Upstream's own `AGENTS.md` is the project's
rulebook and stays as shipped; this file only covers what changes when the Windows target is
cross-compiled and run under Wine. See the repository root's `AGENTS.md` for the shared
environment (game dump, prefixes, data dirs, PortWatch standings).

## Build

```sh
cargo build --release -p xcl --target x86_64-pc-windows-gnu
```

`target/x86_64-pc-windows-gnu/release/xcl.exe` (140 MB, PE32+ console). The mingw link builds
the whole workspace member unchanged: `retour` detours, `libudis86-sys`, the `.CRT$XLY` TLS
callback section and the raw-dylib imports all link. Upstream targets `x86_64-pc-windows-msvc`
only and states the crate does not build or run on Linux; that statement is about the MSVC
target and stays true for it.

Fallback when a fault looks ABI-shaped (detours, TLS callbacks, import thunks): build the same
tree for the upstream target with `cargo xwin build --release -p xcl --target
x86_64-pc-windows-msvc` (needs `cargo-xwin`, `clang-cl`, `lld-link`; downloads the MS CRT and
Windows SDK into `~/.cache/cargo-xwin`).

Do not run `cargo fmt` (upstream forbids it, the tree is not rustfmt-clean) and do not commit
build tooling to `main`: this branch (`linux-proton`) is where `scripts/linux/` lives.

## Run

```sh
./scripts/linux/xcl.sh version
./scripts/linux/xcl.sh inspect          # game exe imports, no GPU needed
./scripts/linux/xcl.sh run              # GTA VI dump, logged to the data dir
XCL_APRESS=12 ./scripts/linux/xcl.sh run   # same, pressing pad A (Enter) past the menus
```

`scripts/linux/xcl.sh` is the launcher: `Z:` paths, `XCL_DATA_ROOT`, `XCL_DXC_DIR`,
`WINEDLLOVERRIDES`, `VKD3D_CONFIG`, prefix and window geometry all come from environment
variables with defaults for this machine. `scripts/linux/place-window.sh` pins the window and
`scripts/linux/press-a.sh` sends the A presses; the launcher starts both when `XCL_APRESS` is
non-zero.

- **Prefix**: `/mnt/games/xcl-prefix` (GE-Proton11-1's `files/bin/wine`, `pfx/` inside). A
  prefix created by bare Wine has Wine's own `d3d12.dll`/`d3d12core.dll`, a stub that answers
  `E_NOTIMPL` for `D3D12GetInterface`; the launcher copies vkd3d-proton's pair from
  `files/lib/wine/vkd3d-proton/x86_64-windows/` and `libvkd3d-*.dll` from
  `files/lib/vkd3d/x86_64-windows/` into `system32` when they differ.
- **`WINEDLLOVERRIDES="d3d12=n;d3d12core=n"`** makes Wine load those copies. `dxgi` stays Wine's
  builtin, which vkd3d-proton expects.
- **DXC**: `dxcompiler.dll` + `dxil.dll` (DXC 1.9.2609) in `/mnt/games/xcl-data/dxc`, exported as
  `XCL_DXC_DIR`. Both are loaded by absolute path, so no `dxil` override is needed.
- **XGameRuntime**: Wine has no `System32\xgameruntime.dll`. XCL's preflight only warns (its own
  task queues, async and networking are used); dialogs, text entry, invites and streaming are the
  parts that are missing.
- **Pad A from the shell**: `hle::kbm` maps Enter/Space to A while the XCL window has focus, on
  top of any real controller, so `xdotool key Return` after `windowactivate` is enough.
- **Gamepad focus**: the window keeps the mouse held; `windowactivate` first, then send keys.

## Data

`/mnt/games/xcl-data` is `XCL_DATA_ROOT`: `<title>/xcl.toml`, `overlay/`, `saves/`, `pls/`,
`temp/`, `cache/`, `logs/xcl.log` and `logs/report.json`. Nothing here is committed, and the game
folder is never written to.
