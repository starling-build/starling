// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// An encrypted Office package (MS-OFFCRYPTO): the zip inside an OLE
// compound file, as `EncryptedPackage` beside the `EncryptionInfo` that
// says how to unlock it — Standard encryption (AES-ECB, a SHA-1 key; Office
// 2007) or Agile (AES-CBC, SHA-1 or SHA-512 keys; Office 2010 on).
//
// Excel opens a workbook locked with its built-in password,
// "VelvetSweatshop", without asking (a sheet protected against changes
// is saved that way): 58616's 20 pages print in Excel's run and failed
// here as "not a zip". A file with a password of its own asks for it.
// Foundation has no AES or SHA on Linux or Windows, so they are here,
// for decrypting only.

import Foundation

enum OfficeCrypto {
    /// The password Excel tries itself.
    static let defaultPassword = "VelvetSweatshop"

    /// An OLE compound file's first bytes.
    static func isCompoundFile(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 512 && bytes[0 ..< 8].elementsEqual([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])
    }

    enum Failure: Error {
        /// Not an encrypted package (another compound file: a .xls, a .doc).
        case notEncrypted
        /// Encrypted, and the password does not open it.
        case wrongPassword
        case unsupported(String)
        case corrupt(String)
    }

    /// The package's zip, unlocked with `password`.
    static func decrypt(_ bytes: [UInt8], password: String = defaultPassword) throws -> [UInt8] {
        let file = try CompoundFile(bytes)
        guard let info = file.stream("EncryptionInfo"), let package = file.stream("EncryptedPackage") else { throw Failure.notEncrypted }
        guard info.count >= 8, package.count >= 8 else { throw Failure.corrupt("encryption info") }
        let major = u16(info, 0), minor = u16(info, 2)
        switch (major, minor) {
        case (4, 4): return try _agile(info, package, password)
        case (2, 2), (3, 2), (4, 2): return try _standard(info, package, password)
        default: throw Failure.unsupported("encryption \(major).\(minor)")
        }
    }

    // MARK: Standard

    private static func _standard(_ info: [UInt8], _ package: [UInt8], _ password: String) throws -> [UInt8] {
        let headerSize = Int(u32(info, 8))
        let h = 12
        guard h + headerSize + 4 <= info.count, headerSize >= 32 else { throw Failure.corrupt("encryption header") }
        let algID = u32(info, h + 8), keyBits = Int(u32(info, h + 16))
        guard algID == 0x660E || algID == 0x660F || algID == 0x6610 else { throw Failure.unsupported("cipher \(algID)") }
        var v = h + headerSize
        let saltSize = Int(u32(info, v))
        v += 4
        guard v + saltSize + 16 + 4 + 32 <= info.count else { throw Failure.corrupt("verifier") }
        let salt = Array(info[v ..< v + saltSize])
        let verifier = Array(info[v + saltSize ..< v + saltSize + 16])
        let hashStart = v + saltSize + 16 + 4
        let verifierHash = Array(info[hashStart ..< hashStart + 32])

        // The key: the password's hash spun 50,000 times, then stretched
        // as CryptDeriveKey stretches it.
        var hash = SHA1.hash(salt + utf16(password))
        for i in 0 ..< 50_000 { hash = SHA1.hash(le32(UInt32(i)) + hash) }
        let final = SHA1.hash(hash + le32(0))
        var b1 = [UInt8](repeating: 0x36, count: 64), b2 = [UInt8](repeating: 0x5C, count: 64)
        for i in 0 ..< final.count { b1[i] ^= final[i]; b2[i] ^= final[i] }
        let key = Array((SHA1.hash(b1) + SHA1.hash(b2)).prefix(keyBits / 8))
        let aes = try AES(key: key)

        let plainVerifier = aes.decryptECB(verifier)
        guard Array(aes.decryptECB(verifierHash).prefix(20)) == SHA1.hash(plainVerifier) else { throw Failure.wrongPassword }
        let size = Int(min(u64(package, 0), UInt64(package.count)))
        let body = Array(package[8...].prefix((package.count - 8) / 16 * 16))
        return Array(aes.decryptECB(body).prefix(size))
    }

    // MARK: Agile

    private static func _agile(_ info: [UInt8], _ package: [UInt8], _ password: String) throws -> [UInt8] {
        guard let root = XNode.parse(Data(info[8...])) else { throw Failure.corrupt("encryption XML") }
        func local(_ n: XNode) -> String { n.name.split(separator: ":").last.map(String.init) ?? n.name }
        func find(_ n: XNode, _ name: String) -> XNode? {
            if local(n) == name { return n }
            for c in n.children { if let f = find(c, name) { return f } }
            return nil
        }
        guard let keyData = find(root, "keyData"), let pk = find(root, "encryptedKey") else { throw Failure.corrupt("encryption XML") }
        func b64(_ n: XNode, _ k: String) -> [UInt8] { n[k].flatMap { Data(base64Encoded: $0) }.map { [UInt8]($0) } ?? [] }
        func hasher(_ n: XNode) throws -> ([UInt8]) -> [UInt8] {
            switch n["hashAlgorithm"] ?? "SHA1" {
            case "SHA1": return SHA1.hash
            case "SHA512": return SHA512.hash
            case let other: throw Failure.unsupported("hash \(other)")
            }
        }
        guard (pk["cipherAlgorithm"] ?? "AES") == "AES", (keyData["cipherAlgorithm"] ?? "AES") == "AES" else {
            throw Failure.unsupported("cipher")
        }
        // The password's key, for each of the blocks it unlocks.
        let H = try hasher(pk)
        let spin = Int(pk["spinCount"] ?? "100000") ?? 100_000
        let keyBytes = (Int(pk["keyBits"] ?? "256") ?? 256) / 8
        let salt = b64(pk, "saltValue")
        var hash = H(salt + utf16(password))
        for i in 0 ..< spin { hash = H(le32(UInt32(i)) + hash) }
        func keyFor(_ block: [UInt8]) -> [UInt8] {
            var k = H(hash + block)
            if k.count < keyBytes { k += [UInt8](repeating: 0x36, count: keyBytes - k.count) }
            return Array(k.prefix(keyBytes))
        }
        let iv = Array(salt.prefix(16))
        // The verifier first: a wrong password reads as one, not as a
        // package that is not a zip.
        let input = try AES(key: keyFor([0xFE, 0xA7, 0xD2, 0x76, 0x3B, 0x4B, 0x9E, 0x79])).decryptCBC(b64(pk, "encryptedVerifierHashInput"), iv: iv)
        let expected = try AES(key: keyFor([0xD7, 0xAA, 0x0F, 0x6D, 0x30, 0x61, 0x34, 0x4E])).decryptCBC(b64(pk, "encryptedVerifierHashValue"), iv: iv)
        let inputHash = H(Array(input.prefix(Int(pk["saltSize"] ?? "16") ?? 16)))
        guard Array(expected.prefix(inputHash.count)) == inputHash else { throw Failure.wrongPassword }
        let secret = try AES(key: keyFor([0x14, 0x6E, 0x0B, 0xE7, 0xAB, 0xAC, 0xD0, 0xD6])).decryptCBC(b64(pk, "encryptedKeyValue"), iv: iv)
        let dataKeyBytes = (Int(keyData["keyBits"] ?? "256") ?? 256) / 8
        let aes = try AES(key: Array(secret.prefix(dataKeyBytes)))

        // The package in 4,096-byte segments, each with its own IV.
        let HD = try hasher(keyData)
        let dataSalt = b64(keyData, "saltValue")
        let block = Int(keyData["blockSize"] ?? "16") ?? 16
        let size = Int(min(u64(package, 0), UInt64(package.count)))
        var out: [UInt8] = []
        out.reserveCapacity(size + 4096)
        var at = 8, segment: UInt32 = 0
        while at < package.count, out.count < size {
            let end = min(package.count, at + 4096)
            let chunk = Array(package[at ..< at + (end - at) / 16 * 16])
            let segIV = Array(HD(dataSalt + le32(segment)).prefix(block))
            out += aes.decryptCBC(chunk, iv: segIV)
            at = end
            segment += 1
        }
        return Array(out.prefix(size))
    }

    // MARK: Bytes

    fileprivate static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        i + 2 <= b.count ? UInt16(b[i]) | UInt16(b[i + 1]) << 8 : 0
    }
    fileprivate static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        i + 4 <= b.count ? UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24 : 0
    }
    fileprivate static func u64(_ b: [UInt8], _ i: Int) -> UInt64 {
        UInt64(u32(b, i)) | UInt64(u32(b, i + 4)) << 32
    }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)]
    }
    private static func utf16(_ s: String) -> [UInt8] {
        s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }
    }
}

// MARK: - OLE compound file

/// The streams of a compound file (MS-CFB), read by name: what an
/// encrypted package keeps its two streams in.
private struct CompoundFile {
    private let bytes: [UInt8]
    private let sectorSize: Int
    private let miniSectorSize: Int
    private let miniCutoff: Int
    private var fat: [UInt32] = []
    private var miniFat: [UInt32] = []
    private var entries: [(name: String, type: UInt8, start: UInt32, size: Int)] = []
    private var miniStream: [UInt8] = []

    init(_ bytes: [UInt8]) throws {
        guard OfficeCrypto.isCompoundFile(bytes) else { throw OfficeCrypto.Failure.notEncrypted }
        self.bytes = bytes
        let u16 = OfficeCrypto.u16, u32 = OfficeCrypto.u32
        sectorSize = 1 << Int(u16(bytes, 0x1E))
        miniSectorSize = 1 << Int(u16(bytes, 0x20))
        miniCutoff = Int(u32(bytes, 0x38))
        guard (512 ... 4096).contains(sectorSize), (16 ... 512).contains(miniSectorSize) else {
            throw OfficeCrypto.Failure.corrupt("compound file header")
        }
        // The FAT's sectors: 109 in the header, the rest down the DIFAT chain.
        var fatSectors: [UInt32] = (0 ..< 109).map { u32(bytes, 0x4C + $0 * 4) }
        var difat = u32(bytes, 0x44)
        var hops = 0
        while difat < 0xFFFF_FFFA, hops < 10_000 {
            let base = Int(difat + 1) * sectorSize
            let per = sectorSize / 4 - 1
            fatSectors += (0 ..< per).map { u32(bytes, base + $0 * 4) }
            difat = u32(bytes, base + per * 4)
            hops += 1
        }
        for s in fatSectors where s < 0xFFFF_FFFA {
            let base = Int(s + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { continue }
            fat += (0 ..< sectorSize / 4).map { u32(bytes, base + $0 * 4) }
        }
        // The directory, then the mini stream and its FAT.
        let dir = chain(u32(bytes, 0x30))
        for k in 0 ..< dir.count / 128 {
            let e = k * 128
            let nameLen = Int(u16(dir, e + 64))
            let units = (0 ..< max(0, min(32, nameLen / 2 - 1))).map { UInt16(dir[e + $0 * 2]) | UInt16(dir[e + $0 * 2 + 1]) << 8 }
            let size = Int(OfficeCrypto.u64(dir, e + 120) & (sectorSize == 512 ? 0xFFFF_FFFF : .max))
            entries.append((String(decoding: units, as: UTF16.self), dir[e + 66], u32(dir, e + 116), size))
        }
        if let root = entries.first(where: { $0.type == 5 }) {
            miniStream = Array(chain(root.start).prefix(root.size))
            let mf = chain(u32(bytes, 0x3C))
            miniFat = (0 ..< mf.count / 4).map { u32(mf, $0 * 4) }
        }
    }

    /// The sectors from `start` on, joined.
    private func chain(_ start: UInt32) -> [UInt8] {
        var out: [UInt8] = []
        var s = start
        var seen = 0
        while s < 0xFFFF_FFFA, Int(s) < fat.count, seen <= fat.count {
            let base = Int(s + 1) * sectorSize
            guard base + sectorSize <= bytes.count else { break }
            out += bytes[base ..< base + sectorSize]
            s = fat[Int(s)]
            seen += 1
        }
        return out
    }

    func stream(_ name: String) -> [UInt8]? {
        guard let e = entries.first(where: { $0.type == 2 && $0.name == name }) else { return nil }
        if e.size >= miniCutoff { return Array(chain(e.start).prefix(e.size)) }
        var out: [UInt8] = []
        var s = e.start
        var seen = 0
        while s < 0xFFFF_FFFA, Int(s) < miniFat.count, seen <= miniFat.count {
            let base = Int(s) * miniSectorSize
            guard base + miniSectorSize <= miniStream.count else { break }
            out += miniStream[base ..< base + miniSectorSize]
            s = miniFat[Int(s)]
            seen += 1
        }
        return Array(out.prefix(e.size))
    }
}

// MARK: - Hashes

enum SHA1 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var m = message
        let bits = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in (0 ..< 8).reversed() { m.append(UInt8(bits >> (UInt64(i) * 8) & 0xFF)) }
        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: m.count, by: 64) {
            for i in 0 ..< 16 {
                let j = chunk + i * 4
                w[i] = UInt32(m[j]) << 24 | UInt32(m[j + 1]) << 16 | UInt32(m[j + 2]) << 8 | UInt32(m[j + 3])
            }
            for i in 16 ..< 80 { w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotl(1) }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0 ..< 80 {
                let (f, k): (UInt32, UInt32)
                switch i {
                case 0 ..< 20: (f, k) = ((b & c) | (~b & d), 0x5A82_7999)
                case 20 ..< 40: (f, k) = (b ^ c ^ d, 0x6ED9_EBA1)
                case 40 ..< 60: (f, k) = ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC)
                default: (f, k) = (b ^ c ^ d, 0xCA62_C1D6)
                }
                let t = a.rotl(5) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = b.rotl(30); b = a; a = t
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e
        }
        return h.flatMap { v in (0 ..< 4).map { UInt8(v >> (24 - UInt32($0) * 8) & 0xFF) } }
    }
}

enum SHA512 {
    private static let k: [UInt64] = [
        0x428a2f98d728ae22, 0x7137449123ef65cd, 0xb5c0fbcfec4d3b2f, 0xe9b5dba58189dbbc, 0x3956c25bf348b538,
        0x59f111f1b605d019, 0x923f82a4af194f9b, 0xab1c5ed5da6d8118, 0xd807aa98a3030242, 0x12835b0145706fbe,
        0x243185be4ee4b28c, 0x550c7dc3d5ffb4e2, 0x72be5d74f27b896f, 0x80deb1fe3b1696b1, 0x9bdc06a725c71235,
        0xc19bf174cf692694, 0xe49b69c19ef14ad2, 0xefbe4786384f25e3, 0x0fc19dc68b8cd5b5, 0x240ca1cc77ac9c65,
        0x2de92c6f592b0275, 0x4a7484aa6ea6e483, 0x5cb0a9dcbd41fbd4, 0x76f988da831153b5, 0x983e5152ee66dfab,
        0xa831c66d2db43210, 0xb00327c898fb213f, 0xbf597fc7beef0ee4, 0xc6e00bf33da88fc2, 0xd5a79147930aa725,
        0x06ca6351e003826f, 0x142929670a0e6e70, 0x27b70a8546d22ffc, 0x2e1b21385c26c926, 0x4d2c6dfc5ac42aed,
        0x53380d139d95b3df, 0x650a73548baf63de, 0x766a0abb3c77b2a8, 0x81c2c92e47edaee6, 0x92722c851482353b,
        0xa2bfe8a14cf10364, 0xa81a664bbc423001, 0xc24b8b70d0f89791, 0xc76c51a30654be30, 0xd192e819d6ef5218,
        0xd69906245565a910, 0xf40e35855771202a, 0x106aa07032bbd1b8, 0x19a4c116b8d2d0c8, 0x1e376c085141ab53,
        0x2748774cdf8eeb99, 0x34b0bcb5e19b48a8, 0x391c0cb3c5c95a63, 0x4ed8aa4ae3418acb, 0x5b9cca4f7763e373,
        0x682e6ff3d6b2b8a3, 0x748f82ee5defb2fc, 0x78a5636f43172f60, 0x84c87814a1f0ab72, 0x8cc702081a6439ec,
        0x90befffa23631e28, 0xa4506cebde82bde9, 0xbef9a3f7b2c67915, 0xc67178f2e372532b, 0xca273eceea26619c,
        0xd186b8c721c0c207, 0xeada7dd6cde0eb1e, 0xf57d4f7fee6ed178, 0x06f067aa72176fba, 0x0a637dc5a2c898a6,
        0x113f9804bef90dae, 0x1b710b35131c471b, 0x28db77f523047d84, 0x32caab7b40c72493, 0x3c9ebe0a15c9bebc,
        0x431d67c49c100d4c, 0x4cc5d4becb3e42b6, 0x597f299cfc657e2a, 0x5fcb6fab3ad6faec, 0x6c44198c4a475817,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt64] = [0x6a09e667f3bcc908, 0xbb67ae8584caa73b, 0x3c6ef372fe94f82b, 0xa54ff53a5f1d36f1,
                           0x510e527fade682d1, 0x9b05688c2b3e6c1f, 0x1f83d9abfb41bd6b, 0x5be0cd19137e2179]
        var m = message
        let bits = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 128 != 112 { m.append(0) }
        m += [UInt8](repeating: 0, count: 8)
        for i in (0 ..< 8).reversed() { m.append(UInt8(bits >> (UInt64(i) * 8) & 0xFF)) }
        var w = [UInt64](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: m.count, by: 128) {
            for i in 0 ..< 16 {
                var v: UInt64 = 0
                for j in 0 ..< 8 { v = v << 8 | UInt64(m[chunk + i * 8 + j]) }
                w[i] = v
            }
            for i in 16 ..< 80 {
                let s0 = w[i - 15].rotr(1) ^ w[i - 15].rotr(8) ^ (w[i - 15] >> 7)
                let s1 = w[i - 2].rotr(19) ^ w[i - 2].rotr(61) ^ (w[i - 2] >> 6)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0 ..< 80 {
                let s1 = e.rotr(14) ^ e.rotr(18) ^ e.rotr(41)
                let ch = (e & f) ^ (~e & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = a.rotr(28) ^ a.rotr(34) ^ a.rotr(39)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] &+= a; h[1] &+= b; h[2] &+= c; h[3] &+= d; h[4] &+= e; h[5] &+= f; h[6] &+= g; h[7] &+= hh
        }
        return h.flatMap { v in (0 ..< 8).map { UInt8(v >> (56 - UInt64($0) * 8) & 0xFF) } }
    }
}

private extension UInt32 {
    func rotl(_ n: UInt32) -> UInt32 { self << n | self >> (32 - n) }
}

private extension UInt64 {
    func rotr(_ n: UInt64) -> UInt64 { self >> n | self << (64 - n) }
}

// MARK: - AES (decryption)

struct AES {
    private static let sbox: [UInt8] = {
        // The multiplicative inverse in GF(2^8), then the affine map.
        var s = [UInt8](repeating: 0, count: 256)
        var p: UInt8 = 1, q: UInt8 = 1
        repeat {
            p = p ^ (p << 1) ^ (p & 0x80 != 0 ? 0x1B : 0)
            q ^= q << 1; q ^= q << 2; q ^= q << 4
            if q & 0x80 != 0 { q ^= 0x09 }
            let r = q ^ (q << 1 | q >> 7) ^ (q << 2 | q >> 6) ^ (q << 3 | q >> 5) ^ (q << 4 | q >> 4)
            s[Int(p)] = r ^ 0x63
        } while p != 1
        s[0] = 0x63
        return s
    }()
    private static let inverse: [UInt8] = {
        var inv = [UInt8](repeating: 0, count: 256)
        for (i, v) in sbox.enumerated() { inv[Int(v)] = UInt8(i) }
        return inv
    }()

    private static func mul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        var a = a, b = b, p: UInt8 = 0
        while b != 0 {
            if b & 1 != 0 { p ^= a }
            a = (a << 1) ^ (a & 0x80 != 0 ? 0x1B : 0)
            b >>= 1
        }
        return p
    }
    private static let m9 = (0 ..< 256).map { mul(UInt8($0), 9) }
    private static let m11 = (0 ..< 256).map { mul(UInt8($0), 11) }
    private static let m13 = (0 ..< 256).map { mul(UInt8($0), 13) }
    private static let m14 = (0 ..< 256).map { mul(UInt8($0), 14) }

    private let rounds: Int
    private let w: [UInt8]   // the expanded key, 16 bytes a round

    init(key: [UInt8]) throws {
        guard [16, 24, 32].contains(key.count) else { throw OfficeCrypto.Failure.unsupported("AES key of \(key.count) bytes") }
        let nk = key.count / 4
        rounds = nk + 6
        var w = key
        var rcon: UInt8 = 1
        for i in nk ..< 4 * (rounds + 1) {
            var t = Array(w[(i - 1) * 4 ..< i * 4])
            if i % nk == 0 {
                t = [AES.sbox[Int(t[1])] ^ rcon, AES.sbox[Int(t[2])], AES.sbox[Int(t[3])], AES.sbox[Int(t[0])]]
                rcon = (rcon << 1) ^ (rcon & 0x80 != 0 ? 0x1B : 0)
            } else if nk > 6, i % nk == 4 {
                t = t.map { AES.sbox[Int($0)] }
            }
            for j in 0 ..< 4 { w.append(w[(i - nk) * 4 + j] ^ t[j]) }
        }
        self.w = w
    }

    /// One 16-byte block, in place at `at`.
    private func decryptBlock(_ s: inout [UInt8], _ at: Int) {
        func addRoundKey(_ r: Int) { for i in 0 ..< 16 { s[at + i] ^= w[r * 16 + i] } }
        addRoundKey(rounds)
        for r in stride(from: rounds - 1, through: 0, by: -1) {
            // Inverse shift rows, inverse substitution.
            var t = [UInt8](repeating: 0, count: 16)
            for c in 0 ..< 4 { for row in 0 ..< 4 { t[((c + row) % 4) * 4 + row] = s[at + c * 4 + row] } }
            for i in 0 ..< 16 { s[at + i] = AES.inverse[Int(t[i])] }
            addRoundKey(r)
            if r > 0 {
                for c in 0 ..< 4 {
                    let a0 = Int(s[at + c * 4]), a1 = Int(s[at + c * 4 + 1]), a2 = Int(s[at + c * 4 + 2]), a3 = Int(s[at + c * 4 + 3])
                    s[at + c * 4] = AES.m14[a0] ^ AES.m11[a1] ^ AES.m13[a2] ^ AES.m9[a3]
                    s[at + c * 4 + 1] = AES.m9[a0] ^ AES.m14[a1] ^ AES.m11[a2] ^ AES.m13[a3]
                    s[at + c * 4 + 2] = AES.m13[a0] ^ AES.m9[a1] ^ AES.m14[a2] ^ AES.m11[a3]
                    s[at + c * 4 + 3] = AES.m11[a0] ^ AES.m13[a1] ^ AES.m9[a2] ^ AES.m14[a3]
                }
            }
        }
    }

    func decryptECB(_ data: [UInt8]) -> [UInt8] {
        var s = Array(data.prefix(data.count / 16 * 16))
        for at in stride(from: 0, to: s.count, by: 16) { decryptBlock(&s, at) }
        return s
    }

    func decryptCBC(_ data: [UInt8], iv: [UInt8]) -> [UInt8] {
        var s = Array(data.prefix(data.count / 16 * 16))
        var prev = Array(iv.prefix(16)) + [UInt8](repeating: 0, count: max(0, 16 - iv.count))
        for at in stride(from: 0, to: s.count, by: 16) {
            let cipher = Array(s[at ..< at + 16])
            decryptBlock(&s, at)
            for i in 0 ..< 16 { s[at + i] ^= prev[i] }
            prev = cipher
        }
        return s
    }
}
