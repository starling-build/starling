// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// X-DA-6 protection: Protect Sheet / Unprotect Sheet with the actions the protected sheet still
// allows and an optional password, Protect Workbook (structure), and locking or hiding the
// selected cells. Protection.swift is what enforces it; this is how it is set and removed.
//
// The password is stored the way Excel stores it. A new one is written as the 16-bit legacy hash
// Excel still reads (`password="83AF"`); one Excel wrote with SHA-512, salt and spin count
// (`hashValue`/`saltValue`/`spinCount`) is checked the same way Excel checks it.

import Foundation

/// What a protected sheet still lets people do (true: allowed). Only what the app enforces is here.
struct SheetProtectionOptions: Equatable {
    var formatCells = false, formatColumns = false, formatRows = false
    var insertColumns = false, insertRows = false, deleteColumns = false, deleteRows = false
    var sort = false, autoFilter = false

    static let keys: [(attr: String, label: String, path: WritableKeyPath<SheetProtectionOptions, Bool>)] = [
        ("formatCells", "Format cells", \.formatCells), ("formatColumns", "Format columns", \.formatColumns),
        ("formatRows", "Format rows", \.formatRows), ("insertColumns", "Insert columns", \.insertColumns),
        ("insertRows", "Insert rows", \.insertRows), ("deleteColumns", "Delete columns", \.deleteColumns),
        ("deleteRows", "Delete rows", \.deleteRows), ("sort", "Sort", \.sort), ("autoFilter", "Use AutoFilter", \.autoFilter),
    ]
}

enum ProtectionProblem: Equatable {
    case wrongPassword, unsupportedPassword, notProtected
    var message: String {
        switch self {
        case .wrongPassword: return "The password you supplied is not correct."
        case .unsupportedPassword: return "This protection uses a password method this app cannot check. Remove it in Excel."
        case .notProtected: return "Nothing is protected here."
        }
    }
}

enum ProtectionPassword {
    /// Excel's 16-bit password hash, as four hex digits.
    static func legacy(_ password: String) -> String {
        let chars = Array(password.utf16)
        var h: UInt32 = 0
        for (i, c) in chars.enumerated() {
            let v = UInt32(c) << UInt32(i + 1)
            h ^= (v & 0x7FFF) | (v >> 15)
        }
        h ^= UInt32(chars.count)
        h ^= 0xCE4B
        let hex = String(h & 0xFFFF, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 4 - hex.count)) + hex
    }

    /// Excel's salted, spun SHA-512 hash, base64.
    static func sha512(_ password: String, salt: [UInt8], spin: Int) -> String {
        var h = SHA512.hash(salt + password.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] })
        for i in 0 ..< max(0, spin) {
            let n = UInt32(i)
            h = SHA512.hash(h + [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8(n >> 24)])
        }
        return Data(h).base64EncodedString()
    }

    /// Whether `password` opens a protection element whose attributes use `prefix` ("" for a sheet, "workbook" for the book).
    /// nil: the element holds a hash method this cannot check.
    static func accepts(_ a: [String: String], prefix: String, _ password: String) -> Bool? {
        func key(_ k: String) -> String { prefix.isEmpty ? k : prefix + String(k.prefix(1)).uppercased() + String(k.dropFirst()) }
        if let hash = a[key("hashValue")] {
            guard (a[key("algorithmName")] ?? "SHA-512") == "SHA-512",
                  let salt = a[key("saltValue")].flatMap({ Data(base64Encoded: $0) }) else { return nil }
            return sha512(password, salt: [UInt8](salt), spin: Int(a[key("spinCount")] ?? "") ?? 100_000) == hash
        }
        if let legacy = a[prefix.isEmpty ? "password" : "workbookPassword"] { return legacy.uppercased() == Self.legacy(password) }
        return true
    }
}

extension WorkbookController {
    /// The active sheet's protection as set (nil when it is not protected).
    func sheetProtectionOptions() -> SheetProtectionOptions? {
        guard let p = protection() else { return nil }
        var o = SheetProtectionOptions()
        for k in SheetProtectionOptions.keys { o[keyPath: k.path] = p[k.attr] == "0" || p[k.attr] == "false" }
        return o
    }

    /// Whether the active sheet's protection has a password.
    var sheetHasPassword: Bool {
        guard let p = protection() else { return false }
        return p["password"] != nil || p["hashValue"] != nil
    }

    var workbookHasPassword: Bool {
        book.workbookProtection?["workbookPassword"] != nil || book.workbookProtection?["workbookHashValue"] != nil
    }

    /// Protect the active sheet: nothing but `allow` can be done to its locked cells. The password may be empty.
    @discardableResult
    func protectSheet(_ allow: SheetProtectionOptions, password: String) -> ProtectionProblem? {
        let ws = sheet
        var kept: [String: String] = [:]
        // What the app does not offer stays as the file had it.
        if let old = protection() { for k in ["objects", "scenarios", "selectLockedCells", "selectUnlockedCells", "insertHyperlinks", "pivotTables"] { kept[k] = old[k] } }
        var a: [String: String] = kept.compactMapValues { $0 }
        a["sheet"] = "1"
        for k in SheetProtectionOptions.keys { a[k.attr] = allow[keyPath: k.path] ? "0" : "1" }
        if !password.isEmpty { a["password"] = ProtectionPassword.legacy(password) }
        let text = "<sheetProtection" + a.keys.sorted().map { " \($0)=\"\(a[$0] ?? "")\"" }.joined() + "/>"
        structural {
            if let i = ws.keptElements.firstIndex(where: { $0.name == "sheetProtection" }) { ws.keptElements[i].text = text }
            else { ws.keptElements.append(("sheetProtection", text)) }
        }
        return nil
    }

    /// Remove the active sheet's protection; the password, if it has one, must match.
    @discardableResult
    func unprotectSheet(password: String) -> ProtectionProblem? {
        guard let p = protection() else { return .notProtected }
        guard let ok = ProtectionPassword.accepts(p, prefix: "", password) else { return .unsupportedPassword }
        guard ok else { return .wrongPassword }
        let ws = sheet
        structural { ws.keptElements.removeAll { $0.name == "sheetProtection" } }
        return nil
    }

    /// Lock the workbook's structure (sheets cannot be added, removed, renamed, hidden or shown).
    func protectWorkbook(password: String) {
        structural {
            var a = book.workbookProtection ?? [:]
            for k in ["workbookPassword", "workbookHashValue", "workbookSaltValue", "workbookSpinCount", "workbookAlgorithmName"] { a[k] = nil }
            a["lockStructure"] = "1"
            if !password.isEmpty { a["workbookPassword"] = ProtectionPassword.legacy(password) }
            book.workbookProtection = a
        }
    }

    @discardableResult
    func unprotectWorkbook(password: String) -> ProtectionProblem? {
        guard let p = book.workbookProtection, book.structureLocked else { return .notProtected }
        guard let ok = ProtectionPassword.accepts(p, prefix: "workbook", password) else { return .unsupportedPassword }
        guard ok else { return .wrongPassword }
        structural {
            var a = book.workbookProtection ?? [:]
            for k in ["workbookPassword", "workbookHashValue", "workbookSaltValue", "workbookSpinCount", "workbookAlgorithmName", "lockStructure"] { a[k] = nil }
            // lockWindows and others stay; nothing left means no element.
            book.workbookProtection = a.isEmpty ? nil : a
        }
        return nil
    }

    /// Lock or unlock, and show or hide the formulas of, the selected cells (Format Cells > Protection). nil leaves it as it is.
    func setCellProtection(locked: Bool?, formulaHidden: Bool?) {
        var e = CellFormatEdit()
        if let locked { e.locked = .set(locked) }
        if let formulaHidden { e.formulaHidden = .set(formulaHidden) }
        formatCells(e)
    }
}
