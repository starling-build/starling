// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// What Sheets prints: the active sheet, the entire workbook, or the selection (the shared
// Print dialog's "Print what" choices).
import Flutter
import FlutterSwiftBridge

enum PrintWhat: Equatable {
    case activeSheet, entireWorkbook, selection
    var label: String {
        switch self {
        case .activeSheet: return "Active sheet"
        case .entireWorkbook: return "Entire workbook"
        case .selection: return "Selection"
        }
    }
}
