// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Flutter
import FlutterSwiftBridge
import Foundation

// MARK: - CalculatorApp

class CalculatorApp: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _CalculatorAppState()
    }
}

/// macOS-Calculator-style palette for both appearances. Operator keys stay
/// brand orange in both.
private struct CalcPalette {
    let background: Color
    let displayText: Color
    let digitKey: Color
    let digitKeyText: Color
    let functionKey: Color
    let functionKeyText: Color
    let operatorKey: Color
    let operatorKeyText: Color
    /// Shows through the 1px gaps between keys.
    let keyGap: Color

    init(dark: Bool) {
        if dark {
            background = Color(0xA62A2C33)
            displayText = Color(0xFFFFFFFF)
            digitKey = Color(0xD957575A)
            digitKeyText = Color(0xFFFFFFFF)
            functionKey = Color(0xD9454548)
            functionKeyText = Color(0xFFFFFFFF)
            operatorKey = Color(0xFFFF9F0A)
            operatorKeyText = Color(0xFFFFFFFF)
            keyGap = Color(0x00000000)
        } else {
            background = Color(0xCCECECEE)
            displayText = Color(0xFF1D1D1F)
            digitKey = Color(0xFFFBFBFB)
            digitKeyText = Color(0xFF1D1D1F)
            functionKey = Color(0xFFDCDCDC)
            functionKeyText = Color(0xFF1D1D1F)
            operatorKey = Color(0xFFFF9F0A)
            operatorKeyText = Color(0xFFFFFFFF)
            keyGap = Color(0x00000000)
        }
    }
}

class _CalculatorAppState: State<StatefulWidget>, @unchecked Sendable {

    private var engine = CalculatorEngine()
    private var pal = CalcPalette(dark: true)

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        pal = CalcPalette(dark: theme.brightness == .dark)

        return DecoratedBox(
            decoration: BoxDecoration(color: pal.background),
            child: Column(children: [
                Expanded(flex: 4, child: _display()),
                Expanded(flex: 3, child: _row([
                    _functionKey(engine.isCleared ? "AC" : "C") { [self] in
                        if engine.isCleared {
                            engine.clearAll()
                        } else {
                            engine.clearEntry()
                        }
                    },
                    _functionKey("±") { [self] in engine.toggleSign() },
                    _functionKey("%") { [self] in engine.percent() },
                    _operatorKey("÷", .divide),
                ])),
                Expanded(flex: 3, child: _row([
                    _digitKey(7), _digitKey(8), _digitKey(9),
                    _operatorKey("×", .multiply),
                ])),
                Expanded(flex: 3, child: _row([
                    _digitKey(4), _digitKey(5), _digitKey(6),
                    _operatorKey("−", .subtract),
                ])),
                Expanded(flex: 3, child: _row([
                    _digitKey(1), _digitKey(2), _digitKey(3),
                    _operatorKey("+", .add),
                ])),
                Expanded(flex: 3, child: _row([
                    _key("0", bg: pal.digitKey, fg: pal.digitKeyText, flex: 2) {
                        [self] in engine.digit(0)
                    },
                    _key(".", bg: pal.digitKey, fg: pal.digitKeyText) {
                        [self] in engine.dot()
                    },
                    _key("=", bg: pal.operatorKey, fg: pal.operatorKeyText, fontSize: 24) {
                        [self] in engine.equals()
                    },
                ])),
            ])
        )
    }

    // MARK: - Pieces

    private func _display() -> Widget {
        let text = engine.display
        // Shrink long results so they stay inside the window.
        let fontSize: Double = text.count > 9 ? 26 : 40
        return Align(
            alignment: Alignment.bottomRight,
            child: Padding(
                padding: EdgeInsets(horizontal: 16, vertical: 8),
                child: Text(
                    text,
                    style: TextStyle(
                        color: pal.displayText,
                        fontSize: fontSize,
                        fontWeight: .w300
                    )
                )
            )
        )
    }

    /// A key row: children separated by 1px gaps over the keyGap color.
    private func _row(_ keys: [Widget]) -> Widget {
        var children: [Widget] = []
        for (i, key) in keys.enumerated() {
            if i > 0 { children.append(SizedBox(width: 1)) }
            children.append(key)
        }
        return Padding(
            padding: EdgeInsets(top: 1),
            child: Row(children: children)
        )
    }

    private func _digitKey(_ d: Int) -> Widget {
        return _key(String(d), bg: pal.digitKey, fg: pal.digitKeyText) {
            [self] in engine.digit(d)
        }
    }

    private func _functionKey(_ label: String, onTap: @escaping () -> Void) -> Widget {
        return _key(label, bg: pal.functionKey, fg: pal.functionKeyText, fontSize: 18, onTap: onTap)
    }

    /// Operator keys invert (white on orange -> orange on white) while their
    /// operation is pending, like macOS Calculator.
    private func _operatorKey(_ label: String, _ op: CalcOp) -> Widget {
        let active = engine.activeOp == op
        return _key(
            label,
            bg: active ? Color(0xFFFFFFFF) : pal.operatorKey,
            fg: active ? pal.operatorKey : pal.operatorKeyText,
            fontSize: 24
        ) { [self] in engine.setOp(op) }
    }

    private func _key(
        _ label: String,
        bg: Color,
        fg: Color,
        flex: Int = 1,
        fontSize: Double = 20,
        onTap: @escaping () -> Void
    ) -> Widget {
        return Expanded(
            flex: flex,
            child: GestureDetector(
                onTap: { [self] in setState { onTap() } },
                behavior: .opaque,
                child: DecoratedBox(
                    decoration: BoxDecoration(color: bg),
                    child: Center(
                        child: Text(
                            label,
                            style: TextStyle(color: fg, fontSize: fontSize)
                        )
                    )
                )
            )
        )
    }
}
