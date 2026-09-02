#!/bin/sh
# Build the Triton host stack into /opt/triton: DXVK (native, headless) as
# the D3D11 backend, UTM's virglrenderer with the Neptune renderer, and UTM's
# QEMU fork, which is the only QEMU that advertises the Neptune capset
# (VIRTIO_GPU_CAPSET_NEPTUNE) and takes the `neptune=on` device property.
#
#   sudo apt build-dep qemu; sudo apt install meson ninja-build glslang-tools \
#       git libepoxy-dev libvulkan-dev libdrm-dev libgbm-dev
#   docs/windows-vm/triton/build-host.sh [srcdir]     # default ~/src/triton
#
# Commits are pinned to what was evaluated (2026-09); bump deliberately, and
# bump virglrenderer and the guest package TOGETHER: the Neptune wire protocol
# is not versioned. The v0.3 guest (2026-08-30) against the `neptune` branch
# tip (2026-07-25) desynchronised the command stream on DWM's first present
# ("unknown transport command: subgroup=0 method=11", worker SIGSEGV) --
# the host side of that guest lives on `macos-next`, whatever the name says.
# Four QEMU patches ride along (patches/): 0001-0003 are bugs found with the
# stock 10.2.1 `-display dbus` in Part A of docs/plans/windows-home-vm.md and
# still present in utm-edition; 0004 only shows with a guest that flips:
#   0001  guest reset with a listener registered asserts in
#         dbus_scanout_texture (no EGL context current when the console
#         switches surfaces)
#   0002  a listener that disconnects stays registered (filter ref cycle);
#         upstream b6506de40f, not in 10.0.x/10.2.x
#   0003  guest-to-host clipboard: the Windows vd_agent never announces
#         VD_AGENT_CAP_CLIPBOARD_GRAB_SERIAL, and dbus-clipboard dropped
#         its serial-less grabs
#   0004  a flip-model guest (DWM on Triton: SET_SCANOUT_BLOB every frame)
#         got a Disable after every frame -- releasing the buffer it just
#         flipped away from was treated as the display going away -- and
#         the Disable's discard mark made the dbus filter drop the
#         ScanoutDMABUF for the new buffer, so a listener kept a stale
#         frame (measured 224 Update, 223 Disable, 22 ScanoutDMABUF).
#         Release of a superseded buffer is now a no-op. Same code in
#         upstream ui/dbus-listener.c.
set -eu

PREFIX=${PREFIX:-/opt/triton}
SRC=${1:-$HOME/src/triton}
JOBS=${JOBS:-$(nproc)}
HERE=$(cd "$(dirname "$0")" && pwd)

DXVK_REPO=https://github.com/osy/dxvk.git
DXVK_COMMIT=404240fdacf4          # master 2026-07-17
VIRGL_REPO=https://github.com/utmapp/virglrenderer.git
VIRGL_COMMIT=482f9d8b             # macos-next 2026-08-31 (the Neptune mainline; `neptune` stopped 2026-07-25)
QEMU_REPO=https://github.com/utmapp/qemu.git
QEMU_COMMIT=227f8b678b0f          # utm-edition 2026-08-30 (10.0.12 base)

LIBDIR=$PREFIX/lib/x86_64-linux-gnu
export PKG_CONFIG_PATH=$LIBDIR/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}

clone() { # repo commit dir [submodule ...]
    # Only the named submodules are initialised: QEMU's roms/ tree (edk2 and
    # its own submodules) is hundreds of MB the x86 build never reads, since
    # the firmware blobs are prebuilt under pc-bios/.
    local repo=$1 commit=$2 dir=$3; shift 3
    if [ ! -d "$dir/.git" ]; then
        git clone "$repo" "$dir"
    fi
    git -C "$dir" fetch -q origin
    git -C "$dir" checkout -q "$commit"
    if [ $# -gt 0 ]; then
        git -C "$dir" submodule update --init --recursive -q "$@"
    fi
}

mkdir -p "$SRC"
cd "$SRC"

# 1. DXVK native, no window system: Neptune dlopens libdxvk_d3d11.so and
#    libdxvk_dxgi.so (NPT_D3D11_LIBRARY_PATH / NPT_DXGI_LIBRARY_PATH) and
#    presents through virtio-gpu blobs, so no SDL/GLFW WSI is wanted.
clone $DXVK_REPO $DXVK_COMMIT dxvk include/native include/spirv include/vulkan subprojects/dxbc-spirv subprojects/libdisplay-info
meson setup dxvk/build dxvk --reconfigure --prefix="$PREFIX" --libdir="$LIBDIR" \
    --buildtype=release -Dnative_headless=true \
    -Dnative_sdl2=disabled -Dnative_sdl3=disabled -Dnative_glfw=disabled \
    -Denable_d3d8=false -Denable_d3d9=false
ninja -C dxvk/build -j"$JOBS"
sudo ninja -C dxvk/build install

# 2. virglrenderer with Neptune (implies the render server; the Neptune
#    renderer runs in the virgl_render_server worker, one process per
#    context). venus too, so a Vulkan guest ICD works on the same device.
clone $VIRGL_REPO $VIRGL_COMMIT virglrenderer
meson setup virglrenderer/build virglrenderer --reconfigure --prefix="$PREFIX" --libdir="$LIBDIR" \
    --buildtype=release -Dneptune=true -Dvenus=true -Dvtest=false -Dtests=false \
    -Dcheck-gl-errors=false -Drender-server-worker=process
ninja -C virglrenderer/build -j"$JOBS"
sudo ninja -C virglrenderer/build install

# 3. UTM's QEMU. x86_64 system emulation only, with the dbus display so
#    Part A's listener (docs/windows-vm/dbus-display.py) is the display.
#    SPICE off: the fork's ui/spice-display.c does not compile on Linux (UTM
#    never builds it) and nothing here uses it. The spice *protocol* (headers
#    only) stays on: it is what builds ui/vdagent.c, i.e. the qemu-vdagent
#    chardev the clipboard rides on.
clone $QEMU_REPO $QEMU_COMMIT qemu
for p in "$HERE"/patches/*.patch; do
    git -C qemu apply --check "$p" 2>/dev/null && git -C qemu apply "$p" || echo "already applied: $p"
done
mkdir -p qemu/build
(cd qemu/build && ../configure --prefix="$PREFIX" --target-list=x86_64-softmmu \
    --enable-kvm --enable-virglrenderer --enable-opengl --enable-dbus-display \
    --disable-spice --enable-spice-protocol --disable-docs --disable-werror \
    --extra-ldflags="-Wl,-rpath,$LIBDIR")
ninja -C qemu/build -j"$JOBS"
sudo ninja -C qemu/build install

echo
echo "installed:"
ls -1 "$PREFIX"/bin/qemu-system-x86_64 "$PREFIX"/libexec/virgl_render_server \
      "$LIBDIR"/libvirglrenderer.so* "$LIBDIR"/libdxvk_d3d11.so "$LIBDIR"/libdxvk_dxgi.so
"$PREFIX"/bin/qemu-system-x86_64 -device virtio-vga-gl,help | grep -E 'neptune|blob|hostmem' || true
