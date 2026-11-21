import Foundation
import Flutter
import FlutterSwiftBridge

/// A four-component (CMYK) JPEG. The codec turns it to RGB the naive way
/// (R = (1-C)(1-K)), which comes out far more saturated than PowerPoint
/// prints it: PowerPoint converts through a press profile (reds near
/// (180,49,41) where the naive result is (195,0,0)). The picture is
/// decoded here and converted through the SWOP press profile.
enum CmykJpeg {
    static func isCmyk(_ b: [UInt8]) -> Bool {
        guard b.count > 4, b[0] == 0xFF, b[1] == 0xD8 else { return false }
        var i = 2
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let m = b[i + 1]
            if m == 0xFF { i += 1; continue }
            if m == 0xD8 || m == 0x01 || (m >= 0xD0 && m <= 0xD7) { i += 2; continue }
            let len = Int(b[i + 2]) << 8 | Int(b[i + 3])
            if m == 0xE2, len >= 16, b[i + 4 ..< i + 15].elementsEqual(Array("ICC_PROFILE".utf8)) { return false }
            if (m >= 0xC0 && m <= 0xCF) && m != 0xC4 && m != 0xC8 && m != 0xCC { return b[i + 9] == 4 }
            if m == 0xDA { return false }
            i += 2 + len
        }
        return false
    }

    /// The inks (0 to 255 each) as sRGB: the usual polynomial fit of the U.S. Web Coated (SWOP)
    /// press profile, which is what a CMYK file with no profile of its own is read as.
    static func rgb(_ c8: UInt8, _ m8: UInt8, _ y8: UInt8, _ k8: UInt8) -> (UInt8, UInt8, UInt8) {
        let c = Double(c8) / 255, m = Double(m8) / 255, y = Double(y8) / 255, k = Double(k8) / 255
        let r = 255 + c * (-4.387332384609988 * c + 54.48615194189176 * m + 18.82290502165302 * y + 212.25662451639585 * k - 285.2331026137004)
            + m * (1.7149763477362134 * m - 5.6096736904047315 * y - 17.873870861415444 * k - 5.497006427196366)
            + y * (-2.5217340131683033 * y - 21.248923337353073 * k + 17.5119270841813)
            + k * (-21.86122147463605 * k - 189.48180835922747)
        let g = 255 + c * (8.841041422036149 * c + 60.118027045597366 * m + 6.871425592049007 * y + 31.159100130055922 * k - 79.2970844816548)
            + m * (-15.310361306967817 * m + 17.575251261109482 * y + 131.35250912493976 * k - 190.9453302588951)
            + y * (4.444339102852739 * y + 9.8632861493405 * k - 24.86741582555878)
            + k * (-20.737325471181034 * k - 187.80453709719578)
        let b = 255 + c * (0.8842522430003296 * c + 8.078677503112928 * m + 30.89978309703729 * y - 0.23883238689178934 * k - 14.183576799673286)
            + m * (10.49593273432072 * m + 63.02378494754052 * y + 50.606957656360734 * k - 112.23884253719248)
            + y * (0.03296041114873217 * y + 115.60384449646641 * k - 193.58209356861505)
            + k * (-22.33816807309886 * k - 180.12613974708367)
        func cl(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v.rounded()))) }
        return (cl(r), cl(g), cl(b))
    }

    /// The picture decoded here and converted through the press profile, as a new image; nil when
    /// the file has a profile of its own (the codec applies it) or is one this decoder does not read.
    @MainActor
    static func decoded(_ bytes: [UInt8]) async -> Image? {
        guard isCmyk(bytes), let d = CmykDecode.decode(bytes), !d.hasICC else { return nil }
        let w = d.width, h = d.height
        var b = [UInt8]()
        let row = w * 3, pad = (4 - row % 4) % 4
        let size = 54 + (row + pad) * h
        b.reserveCapacity(size)
        func u16(_ v: Int) { b += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
        func u32(_ v: Int) { u16(v & 0xFFFF); u16((v >> 16) & 0xFFFF) }
        b += [0x42, 0x4D]; u32(size); u32(0); u32(54)
        u32(40); u32(w); u32(h); u16(1); u16(24); u32(0); u32(size - 54); u32(2835); u32(2835); u32(0); u32(0)
        for y in stride(from: h - 1, through: 0, by: -1) {
            for x in 0 ..< w {
                let o = (y * w + x) * 4
                let c = rgb(d.cmyk[o], d.cmyk[o + 1], d.cmyk[o + 2], d.cmyk[o + 3])
                b += [c.2, c.1, c.0]
            }
            b += [UInt8](repeating: 0, count: pad)
        }
        guard let codec = try? await instantiateImageCodec(b) else { return nil }
        let out = (try? await codec.getNextFrame())?.image
        codec.dispose()
        return out
    }
}
