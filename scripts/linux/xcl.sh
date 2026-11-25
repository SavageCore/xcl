#!/usr/bin/env bash
# xcl.sh - run the Windows xcl.exe under GE-Proton's Wine on Linux.
#
#   ./scripts/linux/xcl.sh inspect [<exe>]      imports and HLE routing, no GPU
#   ./scripts/linux/xcl.sh run [<game folder>]  run the title (folder holds MicrosoftGame.Config)
#   ./scripts/linux/xcl.sh version
#   ./scripts/linux/xcl.sh shell ...            any other xcl.exe arguments
#
# Environment (all optional):
#   XCL_EXE          xcl.exe to launch (default: the windows-gnu release build)
#   XCL_PROTON_DIR   Proton build (default: ~/.steam/steam/compatibilitytools.d/GE-Proton11-1)
#   XCL_PREFIX       Wine prefix (default: /mnt/games/xcl-prefix, pfx/ inside)
#   XCL_DATA_ROOT    XCL data root on Linux (default: /mnt/games/xcl-data)
#   XCL_DXC_DIR      folder with dxcompiler.dll + dxil.dll (default: $XCL_DATA_ROOT/dxc)
#   XCL_GAME         game folder or exe (default: the GTA VI dump)
#   XCL_ADAPTER      d3d12_adapter, e.g. "auto" (default: unset, XCL's choice)
#   XCL_VKD3D_CONFIG VKD3D_CONFIG (default: dxr11,dxr)
#   XCL_APRESS       presses of pad A (Enter) after the window maps, 0 = off
#   XCL_APRESS_AT    seconds after the window maps for those presses (default: 20,30,40,...)
#   XCL_WIN_X/Y/W/H  pin the XCL window there (default: unset, XCL's own geometry)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

XCL_EXE="${XCL_EXE:-$REPO/target/x86_64-pc-windows-gnu/release/xcl.exe}"
XCL_PROTON_DIR="${XCL_PROTON_DIR:-$HOME/.steam/steam/compatibilitytools.d/GE-Proton11-1}"
XCL_PREFIX="${XCL_PREFIX:-/mnt/games/xcl-prefix}"
XCL_DATA_ROOT="${XCL_DATA_ROOT:-/mnt/games/xcl-data}"
XCL_DXC_DIR="${XCL_DXC_DIR:-$XCL_DATA_ROOT/dxc}"
XCL_GAME="${XCL_GAME:-/mnt/games/Shared/GTA6.Xbox.v1.0.2.1-CYBERLEEK}"
XCL_VKD3D_CONFIG="${XCL_VKD3D_CONFIG:-dxr11,dxr,ignore_shared_fence}"

GE_WINE="$XCL_PROTON_DIR/files/bin/wine"

[ -x "$GE_WINE" ] || { echo "xcl.sh: no wine at $GE_WINE" >&2; exit 1; }
[ -f "$XCL_EXE" ] || { echo "xcl.sh: no xcl.exe at $XCL_EXE (build it first)" >&2; exit 1; }
[ -f "$XCL_DXC_DIR/dxcompiler.dll" ] || [ -f "$(dirname "$XCL_EXE")/dxcompiler.dll" ] || {
    echo "xcl.sh: no dxcompiler.dll in $XCL_DXC_DIR or next to xcl.exe" >&2; exit 1; }

# Z: paths: Wine maps the Linux root at Z:
z() { printf 'Z:%s' "$1"; }

mkdir -p "$XCL_PREFIX" "$XCL_DATA_ROOT"

export WINEPREFIX="$XCL_PREFIX/pfx"
# winepulse.drv= : Wine's PulseAudio driver aborts the whole process on
export WINEDLLOVERRIDES="d3d12=n;d3d12core=n;dxgi=n;dxil=n;nvapi64=n;winepulse.drv="

# A prefix made by bare Wine holds Wine's own DLLs, not Proton's set. Proton installs
# DXVK's dxgi + nvapi and vkd3d-proton's d3d12 pair into the prefix; a bare prefix needs
# them copied in. Wine's builtin dxgi (d3d12_swapchain_init) crashes creating a swap chain
# with a vkd3d-proton queue; DXVK's dxgi is the working D3D12 swapchain path.
# libvkd3d-* is what Wine's builtin wined3d and d3dcompiler_47 load against.
install_proton_dlls() {
    local sys="$WINEPREFIX/drive_c/windows/system32" dxvk nvapi vkd3d src
    [ -d "$sys" ] || return 0
    dxvk="$XCL_PROTON_DIR/files/lib/wine/dxvk/x86_64-windows"
    nvapi="$XCL_PROTON_DIR/files/lib/wine/nvapi/x86_64-windows"
    vkd3d="$XCL_PROTON_DIR/files/lib/wine/vkd3d-proton/x86_64-windows"
    for src in "$vkd3d/d3d12.dll" "$vkd3d/d3d12core.dll" "$dxvk/dxgi.dll" "$nvapi/nvapi64.dll" \
               "$XCL_PROTON_DIR"/files/lib/vkd3d/x86_64-windows/*.dll; do
        [ -f "$src" ] || continue
        cmp -s "$src" "$sys/$(basename "$src")" || cp -f "$src" "$sys/" || true
    done
}
# first launch: Wine makes the prefix, then it needs Proton's DLLs
if [ ! -d "$WINEPREFIX/drive_c" ]; then
    "$GE_WINE" wineboot -u >/dev/null 2>&1 || true
fi
install_proton_dlls
export VKD3D_CONFIG="$XCL_VKD3D_CONFIG"
export XCL_DATA_ROOT="$(z "$XCL_DATA_ROOT")"
export XCL_DXC_DIR="$(z "$XCL_DXC_DIR")"
[ -n "${XCL_ADAPTER:-}" ] && export XCL_ADAPTER
[ -n "${XCL_WINDOW_POS:-}" ] && export XCL_WINDOW_POS

cmd="${1:-}"; [ $# -gt 0 ] && shift || true
case "$cmd" in
    version)
        exec "$GE_WINE" "$XCL_EXE" --version
        ;;
    inspect)
        target="${1:-$XCL_GAME/game_scarlett_master.exe}"
        exec "$GE_WINE" "$XCL_EXE" inspect "$(z "$target")"
        ;;
    shell)
        exec "$GE_WINE" "$XCL_EXE" "$@"
        ;;
    run|"")
        target="${1:-$XCL_GAME}"
        ;;
    *)
        echo "usage: xcl.sh [run|inspect|version|shell] [target]" >&2
        exit 2
        ;;
esac

if [ -d "$target" ]; then
    [ -f "$target/MicrosoftGame.Config" ] || [ -f "$target/MicrosoftGame.config" ] || {
        echo "xcl.sh: $target has no MicrosoftGame.Config" >&2; exit 1; }
fi
target_z="$(z "$target")"

# the automation, if asked for, starts before the game does: it waits for the window
if [ "${XCL_APRESS:-0}" != "0" ]; then
    "$HERE/place-window.sh" &
    XCL_APRESS_AT="${XCL_APRESS_AT:-20,30,40,50,60,90,120,180,240,300,420,600}" \
    XCL_APRESS="$XCL_APRESS" "$HERE/press-a.sh" &
fi

cd "$XCL_DATA_ROOT" 2>/dev/null || cd /tmp
echo "xcl.sh: $GE_WINE $XCL_EXE run $target_z"
echo "xcl.sh: data $(z "$XCL_DATA_ROOT") dxc $(z "$XCL_DXC_DIR") prefix $WINEPREFIX"
exec "$GE_WINE" "$XCL_EXE" run "$target_z" "${@:2}"
