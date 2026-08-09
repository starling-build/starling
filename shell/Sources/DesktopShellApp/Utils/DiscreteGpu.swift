// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The render node of the machine's discrete GPU, for PRIME-style app
/// offload (docs/plans/prime.md): apps whose registry record carries
/// `Gpu=discrete` render there while the shell keeps compositing on the
/// display GPU.
///
/// "Discrete" is resolved relative to the shell, not from a vendor list:
/// the first render node backed by a different PCI device than the card
/// the shell renders on (`FLUTTER_DRM_DEVICE` — run-desktop.sh and the
/// session launcher both set it). When that env is absent, fall back to
/// the first render node that is not the boot VGA device — sysfs gives
/// `boot_vga` only to VGA-class devices, and a discrete 3D controller
/// (the dev box's RTX 3050) has no such file at all, so "missing" and
/// "0" both mean not-the-boot-display.
///
/// Single-GPU machine → nil, and `Gpu=discrete` records launch normally.
enum DiscreteGpu {
    static let renderNode: String? = resolve()

    private static func resolve() -> String? {
        // Same-depth relative readlink comparison as the C side's
        // find_render_node_devid (wayland_dmabuf.c): /sys/class/drm entries
        // sit at one depth, so two nodes on one PCI device read back the
        // same "../../../0000:BB:DD.F" string.
        func deviceLink(_ drmName: String) -> String? {
            try? FileManager.default.destinationOfSymbolicLink(
                atPath: "/sys/class/drm/\(drmName)/device")
        }

        var shellLink: String?
        if let card = ProcessInfo.processInfo.environment["FLUTTER_DRM_DEVICE"],
           let name = card.split(separator: "/").last, !name.isEmpty {
            shellLink = deviceLink(String(name))
        }

        for i in 128 ..< 136 {
            let node = "renderD\(i)"
            guard FileManager.default.fileExists(atPath: "/dev/dri/\(node)"),
                  let link = deviceLink(node) else { continue }
            if let shellLink {
                if link != shellLink { return "/dev/dri/\(node)" }
            } else {
                let bootVga = (try? String(
                    contentsOfFile: "/sys/class/drm/\(node)/device/boot_vga",
                    encoding: .utf8))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if bootVga != "1" { return "/dev/dri/\(node)" }
            }
        }
        return nil
    }
}
