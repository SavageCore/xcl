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

- **Prefix**: `/mnt/games/xcl-prefix*` (GE-Proton11-1's `files/bin/wine`, `pfx/` inside). A
  prefix made by bare Wine has Wine's own DLLs, not Proton's set; the launcher copies
  vkd3d-proton's `d3d12.dll`/`d3d12core.dll`, DXVK's `dxgi.dll` (+`nvapi64.dll`) and
  `libvkd3d-*.dll` into `system32` when they differ.
- **`WINEDLLOVERRIDES="d3d12=n;d3d12core=n;dxgi=n;dxil=n;nvapi64=n"`**. `dxgi=n` fails
  when system32 holds Wine's builtin dxgi; it needs DXVK's dxgi there (Wine's builtin
  `d3d12_swapchain_init` crashes creating a swap chain with a vkd3d-proton queue).
- **`VKD3D_CONFIG` always includes `ignore_shared_fence`** (else shared fences hang).
- **DXC**: `dxcompiler.dll` + `dxil.dll` (DXC 1.9.2609) in `/mnt/games/xcl-data/dxc`, exported as
  `XCL_DXC_DIR`. Both are loaded by absolute path, so no `dxil` override is needed.
- **XGameRuntime**: Wine has no `System32\xgameruntime.dll`. XCL's preflight only warns (its own
  task queues, async and networking are used); dialogs, text entry, invites and streaming are the
  parts that are missing.
- **Pad A from the shell**: `hle::kbm` + `gameinput::keyboard` map Enter/Space to A via
  `GetAsyncKeyState` while the XCL window has focus. Polls run ~30 fps: HOLD the key
  (`keydown; sleep 0.3-0.4; keyup`). Taps fall between polls. Arrows = D-pad.
- **ONE instance at a time.** A crashed run's game process can outlive its shell; a second
  instance concurrently shares the GPU and the data dir and hangs pre-present (looks like a
  regression, it is not). Before each run: `pgrep -f "game_scarlett|xcl\.exe run"` must be
  empty (kill strays by PID, never by pattern matching your own shell).

## Upstream picks on this branch (all unmerged upstream, all under `hle/` + scripts)

- XDisplay HDR refusal → `Disabled` (upstream PR #1069).
- In-place vtable adoption breaks vkd3d-proton type checks + shared-fence hangs (PR #867).
- Dedicated PC direct queue for PresentX under Wine (PR #793).
- Console MS in the AS slot translated as the mesh shader (PR #541; its recompiler half
  #304 is already upstream).
- Newer list layout #139 Reset through `title_list::reset` (PR #929, anti-freeze).
- **XG `CopyFromSubresource` takes 8 args, not 7** (own fix): the game's slot-9 call
  sets 4 stack slots; XCL read 6 params, so row/slice pitches were shifted one slot left
  and every readback wrote through wild pointers (deterministic memcpy AV, identical
  stack across runs). Adding the source pitch puts row_pitch/slice_pitch right (verified:
  2048/0x40000 for a 512 BC7 mip0). `copy_into` left alone (its probes vary).

## Current frontier (GTA VI dump, RTX 4080 SUPER, GE-Proton11-1)

Boot → account picker → setup wizard → legal → privacy → main-menu art, all at 30 fps
and screenshotted. Then world streaming (terrain/vehicles/props ttdb reads, BCPack refuses,
audio starts, fps 30 → 9) and death within minutes, three signatures seen: the title GPU
watchdog (write 0 at `game+0x2215c35`), `abort`/exit 3, and a memcpy AV (`msvcrt.dll`,
`game+0x4daa2c8 ← +0x979f5b ← +0x4fb0c2f ← +0x50bb3f0 ← +0x979db0` via `xcl.exe+0xa11f8`,
dst wild, 0x800 bytes — 4 identical occurrences). Best runs: 17 min / 28.5k frames,
25 min to post-setup loading. The streaming crash is probabilistic (survived 2 of ~8 runs),
not prefix- or cache-dependent (ruled out: title dir, vkd3d cache, DXIL/translated cache,
driver blobs, NVIDIA GLCache; the "prefix poison" was concurrent zombie instances).

- `xcl.toml` per title supports `log_level = "debug"` for the full call trace.
- Screenshots: `import -window $(xdotool search --onlyvisible --name '^XCL') shot.png`.
- Title state that matters: `pls/settings/settings.xml` (setup done), `saves/`,
  `gamesave/`, `cache/uma_coherent.txt`. The game folder is never written to.

## Data

`/mnt/games/xcl-data` is `XCL_DATA_ROOT`: `<title>/xcl.toml`, `overlay/` (vkd3d-proton's
disk cache lands here), `saves/`, `pls/`, `temp/`, `cache/`, `logs/xcl.log` and
`logs/report.json` (report.json is only written at exit; xcl.log is the live one).
Nothing here is committed.
