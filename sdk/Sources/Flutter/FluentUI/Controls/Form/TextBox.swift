// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Ported from: fluent_ui/lib/src/controls/form/text_box.dart (simplified)
// This is a simplified text input field. Since the engine doesn't have full
// text input channel support yet, the TextBox displays its text with a cursor
// indicator. Actual text editing is driven via the TextEditingController API.

import FlutterSwiftBridge
import Foundation

// MARK: - TextBox

/// A Fluent UI text input field.
///
/// Displays editable text with a cursor indicator, styled with Fluent UI
/// design tokens (rounded border, proper padding, focus ring).
///
/// Since the engine does not yet have full IME/keyboard input channel support,
/// the TextBox widget structure is in place but actual keyboard-driven editing
/// is limited. Text can be manipulated programmatically via the controller.
public class FluentTextBox: StatefulWidget {
    /// Controls the text being edited.
    /// If nil, a private controller is created internally.
    public let controller: TextEditingController?

    /// A widget displayed when the text field is empty.
    public let placeholder: Widget?

    /// The placeholder text displayed when the text field is empty and no
    /// placeholder widget is provided.
    public let placeholderText: String?

    /// Called when the text changes.
    public let onChanged: ((String) -> Void)?

    /// Called when the user submits the text (e.g. presses Enter).
    public let onSubmitted: ((String) -> Void)?

    /// The maximum number of lines for the text field. Defaults to 1.
    public let maxLines: Int

    /// Whether the text field is read-only.
    public let readOnly: Bool

    /// Whether the text field is enabled.
    public let enabled: Bool

    /// The style of the text in the text field.
    public let style: TextStyle?

    /// The padding inside the text field.
    public let padding: EdgeInsets?

    /// Whether to obscure the text (for password fields).
    public let obscureText: Bool

    /// The character used for obscuring text. Defaults to bullet.
    public let obscuringCharacter: String

    /// The decoration applied to the text box.
    public let decoration: BoxDecoration?

    /// The decoration applied to the text box when focused.
    public let focusedDecoration: BoxDecoration?

    /// Whether the accent focus ring is drawn around the box while it has
    /// focus. It is drawn OUTSIDE `decoration`, so a caller that has supplied
    /// its own chrome gets two rectangles — which is why this exists.
    public let showFocusRing: Bool

    /// The prefix widget displayed before the text.
    public let prefix: Widget?

    /// The suffix widget displayed after the text.
    public let suffix: Widget?

    /// Takes the keyboard as soon as it is mounted.
    ///
    /// A field only receives keys while its focus node is focused, and the
    /// only thing that focused one was a tap. That is fine for a form and
    /// wrong for anything that opens ready to be typed into — a launcher, a
    /// search overlay, a dialog with one field. Those came up looking
    /// perfectly normal and swallowed every keystroke.
    public let autofocus: Bool

    /// Creates a Fluent UI text box.
    public init(
        key: (any Key)? = nil,
        controller: TextEditingController? = nil,
        placeholder: Widget? = nil,
        placeholderText: String? = nil,
        onChanged: ((String) -> Void)? = nil,
        onSubmitted: ((String) -> Void)? = nil,
        maxLines: Int = 1,
        readOnly: Bool = false,
        enabled: Bool = true,
        style: TextStyle? = nil,
        padding: EdgeInsets? = nil,
        obscureText: Bool = false,
        obscuringCharacter: String = "\u{2022}",
        decoration: BoxDecoration? = nil,
        focusedDecoration: BoxDecoration? = nil,
        showFocusRing: Bool = true,
        prefix: Widget? = nil,
        suffix: Widget? = nil,
        autofocus: Bool = false
    ) {
        self.controller = controller
        self.placeholder = placeholder
        self.placeholderText = placeholderText
        self.onChanged = onChanged
        self.onSubmitted = onSubmitted
        self.maxLines = maxLines
        self.readOnly = readOnly
        self.enabled = enabled
        self.style = style
        self.padding = padding
        self.obscureText = obscureText
        self.obscuringCharacter = obscuringCharacter
        self.decoration = decoration
        self.showFocusRing = showFocusRing
        self.focusedDecoration = focusedDecoration
        self.prefix = prefix
        self.suffix = suffix
        self.autofocus = autofocus
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _TextBoxState()
    }
}

// MARK: - _TextBoxState

class _TextBoxState: State<StatefulWidget> {
    private var textBox: FluentTextBox {
        return widget as! FluentTextBox
    }

    /// The effective controller — either user-provided or internally created.
    private var _controller: TextEditingController?
    private var _effectiveController: TextEditingController {
        return textBox.controller ?? _controller!
    }

    /// Whether the text field currently has focus.
    private var _isFocused: Bool = false

    /// Keyboard focus for this field.
    private let _focusNode = FocusNode(debugLabel: "FluentTextBox")

    /// Caret blink state (Ticker-driven; Foundation.Timer does not fire on
    /// the DRM embedder).
    private var _caretVisible: Bool = true
    private var _caretTicker: Ticker?
    #if os(Linux)
    /// True while this box is the reported IME caret target (child-app
    /// shells anchor the IME candidate panel to it).
    private var _reportedImeCaret = false
    #endif

    /// Last text seen, so onChanged only fires for text (not caret) changes.
    private var _lastText: String = ""

    /// Listener callback reference for the controller.
    private let _controllerListener: VoidCallback = {}
    private var _boundListener: VoidCallback?

    override func initState() {
        super.initState()
        if textBox.controller == nil {
            _controller = TextEditingController()
        }
        _lastText = _effectiveController.text
        _boundListener = { [weak self] in
            self?._onControllerChanged()
        }
        _effectiveController.addListener(_boundListener!)

        _focusNode.onFocusChange = { [weak self] focused in
            guard let self = self else { return }
            self.setState {
                self._isFocused = focused
            }
            if focused {
                self._startCaretBlink()
                // A focused field on a touch device has to ask for the keys.
                // Every text field in the framework — Fluent and Macos alike —
                // is this widget underneath, so asking here is what makes them
                // all typable on a phone rather than each wiring its own.
                //
                // Only on gain. Hiding on loss would close the keyboard for the
                // instant between one field blurring and the next focusing,
                // which on a form is every time you move between two fields.
                SoftKeyboard.show()
            } else {
                self._stopCaretBlink()
            }
        }
        _focusNode.onKeyData = { [weak self] keyData in
            return self?._handleKey(keyData) ?? false
        }
        if textBox.autofocus { _focusNode.requestFocus() }
    }

    override func dispose() {
        _stopCaretBlink()
        _focusNode.dispose()
        if let listener = _boundListener {
            _effectiveController.removeListener(listener)
        }
        _controller?.dispose()
        _controller = nil
        super.dispose()
    }

    // MARK: - Key Handling

    // Two numbering schemes reach us, and both have to be recognised — the
    // same split TerminalInput documents at length, and for the same reason.
    //
    // The DRM embedder and the shell's DMA-BUF key forwarding put **X11
    // keysyms** in KeyData.logical. The engine's own embedders — Win32, GTK,
    // Cocoa and UIKit — put **Flutter logical key ids** there instead, which
    // are unrelated values in a plane above 2^32.
    //
    // Printable characters were unaffected either way, because they fall
    // through to keyData.character. Special keys were not, and the failure is
    // quiet and total: on every platform but the Starling shell, backspace
    // deleted nothing, the arrows did not move the caret, and Enter did not
    // submit. That reads as "the field is stuck" rather than as a key id
    // mismatch, and it is what an iOS run made unmissable — a phone has no
    // other way to correct a typo.
    //
    // The two ranges cannot collide (keysyms are 16-bit here, Flutter ids are
    // ≥ 0x1_0000_0000), so one switch serves both.
    private enum _Keysym {
        static let backspace: Int64 = 0xFF08
        static let tab: Int64 = 0xFF09
        static let enter: Int64 = 0xFF0D
        static let escape: Int64 = 0xFF1B
        static let home: Int64 = 0xFF50
        static let left: Int64 = 0xFF51
        static let right: Int64 = 0xFF53
        static let end: Int64 = 0xFF57
        static let kpEnter: Int64 = 0xFF8D
        static let delete: Int64 = 0xFFFF
    }

    /// Flutter logical key ids, as the engine's own embedders deliver them.
    /// Same table as TerminalInput.FlutterKey; kept beside its keysym
    /// counterpart here rather than shared, because the two enums exist to be
    /// read together at the switch below.
    private enum _FlutterKey {
        static let backspace: Int64 = 0x1_0000_0008
        static let tab: Int64 = 0x1_0000_0009
        static let enter: Int64 = 0x1_0000_000D
        static let escape: Int64 = 0x1_0000_001B
        static let delete: Int64 = 0x1_0000_007F
        static let arrowLeft: Int64 = 0x1_0000_0302
        static let arrowRight: Int64 = 0x1_0000_0303
        static let end: Int64 = 0x1_0000_0305
        static let home: Int64 = 0x1_0000_0306
        static let numpadEnter: Int64 = 0x2_0000_020D
    }

    private func _handleKey(_ keyData: KeyData) -> Bool {
        guard keyData.type == .down || keyData.type == .repeat else {
            return false
        }
        guard textBox.enabled else { return false }

        let controller = _effectiveController

        switch keyData.logical {
        case _Keysym.enter, _Keysym.kpEnter,
             _FlutterKey.enter, _FlutterKey.numpadEnter:
            textBox.onSubmitted?(controller.text)
            return true
        case _Keysym.escape, _FlutterKey.escape:
            _focusNode.unfocus()
            return true
        case _Keysym.tab, _FlutterKey.tab:
            return false
        case _Keysym.backspace, _FlutterKey.backspace:
            if !textBox.readOnly { controller.deleteBackward() }
            return true
        case _Keysym.delete, _FlutterKey.delete:
            if !textBox.readOnly { controller.deleteForward() }
            return true
        case _Keysym.left, _FlutterKey.arrowLeft:
            controller.moveCursorLeft()
            return true
        case _Keysym.right, _FlutterKey.arrowRight:
            controller.moveCursorRight()
            return true
        case _Keysym.home, _FlutterKey.home:
            controller.moveCursorToStart()
            return true
        case _Keysym.end, _FlutterKey.end:
            controller.moveCursorToEnd()
            return true
        default:
            break
        }

        // Printable character input (skip control characters — modifiers
        // arrive with no character, Ctrl+letter as 0x00-0x1F, DEL as 0x7F).
        if !textBox.readOnly,
           let character = keyData.character,
           !character.isEmpty,
           let scalar = character.unicodeScalars.first,
           scalar.value >= 0x20, scalar.value != 0x7F {
            controller.insertText(character)
            return true
        }

        return false
    }

    // MARK: - Caret Blink

    private func _startCaretBlink() {
        _caretVisible = true
        _caretTicker?.stop()
        _caretTicker = Ticker({ [weak self] elapsed in
            guard let self = self else { return }
            let comps = elapsed.components
            let ms = comps.seconds * 1_000 + comps.attoseconds / 1_000_000_000_000_000
            let visible = (ms / 530) % 2 == 0
            if visible != self._caretVisible {
                self.setState {
                    self._caretVisible = visible
                }
            }
        }, debugLabel: "TextBox caret blink")
        _ = _caretTicker?.start()
    }

    private func _stopCaretBlink() {
        _caretTicker?.stop()
        _caretTicker = nil
        _caretVisible = true
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let oldTextBox = oldWidget as! FluentTextBox
        if textBox.controller !== oldTextBox.controller {
            if let listener = _boundListener {
                (oldTextBox.controller ?? _controller)?.removeListener(listener)
            }
            if textBox.controller == nil && _controller == nil {
                _controller = TextEditingController()
            }
            if let listener = _boundListener {
                _effectiveController.addListener(listener)
            }
        }
    }

    private func _onControllerChanged() {
        let text = _effectiveController.text
        if text != _lastText {
            _lastText = text
            textBox.onChanged?(text)
        }
        setState {}
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let isEnabled = textBox.enabled
        let isFocused = _isFocused

        #if os(Linux)
        // Report this box to the shell as the IME target while focused —
        // box-anchored: the shell docks its IME candidate panel under the
        // field. Geometry comes from the previous layout (fine: a moved box
        // re-reports on its next rebuild); sendCaret deduplicates.
        if let renderer = GpuDmaBufRenderer.current {
            if isFocused, !textBox.readOnly,
               let box = context.findRenderObject() as? RenderBox,
               box.hasSize {
                let origin = box.localToGlobal(Offset.zero)
                renderer.sendCaret(owner: self, x: origin.dx, y: origin.dy,
                                   width: 2, height: box.size.height,
                                   visible: true)
                _reportedImeCaret = true
            } else if _reportedImeCaret {
                _reportedImeCaret = false
                renderer.sendCaret(owner: self, x: 0, y: 0, width: 0, height: 0,
                                   visible: false)
            }
        }
        #endif

        let effectiveTextStyle = textBox.style ?? TextStyle(
            color: isEnabled
                ? theme.resources.textFillColorPrimary
                : theme.resources.textFillColorDisabled,
            fontSize: 14
        )

        let placeholderStyle = TextStyle(
            color: theme.resources.textFillColorSecondary,
            fontSize: 14
        )

        let effectivePadding = textBox.padding ?? EdgeInsets(
            left: 10, top: 5, right: 10, bottom: 7
        )

        // Build the text display
        let displayText = _effectiveController.text
        let showPlaceholder = displayText.isEmpty

        // Determine the text to display (possibly obscured)
        let visibleText: String
        if textBox.obscureText && !displayText.isEmpty {
            visibleText = String(repeating: textBox.obscuringCharacter, count: displayText.count)
        } else {
            visibleText = displayText
        }

        // Build the cursor indicator (a pipe character at the caret position
        // when focused; a space during blink-off so the layout stays stable).
        let showCaret = isFocused && _caretVisible
        let textWithCursor: String
        if isFocused && !textBox.readOnly {
            let caretGlyph: Character = showCaret ? "|" : " "
            let sel = _effectiveController.selection
            if sel.isValid && sel.isCollapsed && sel.baseOffset >= 0 {
                let cursorPos = Swift.min(sel.baseOffset, visibleText.count)
                let idx = visibleText.index(visibleText.startIndex, offsetBy: cursorPos)
                var mutableText = visibleText
                mutableText.insert(caretGlyph, at: idx)
                textWithCursor = mutableText
            } else {
                textWithCursor = visibleText + String(caretGlyph)
            }
        } else {
            textWithCursor = visibleText
        }

        let textContent: Widget
        if showPlaceholder {
            // While focused, hold layout stable across caret blinks: the
            // caret glyph alternates with a space, not with the placeholder.
            let caretGlyph = showCaret ? "|" : " "
            if let placeholderWidget = textBox.placeholder {
                if isFocused && !textBox.readOnly {
                    // Show cursor even when placeholder is visible
                    textContent = Row(
                        mainAxisSize: .min,
                        children: [
                            Text(caretGlyph, style: effectiveTextStyle),
                            Expanded(child: placeholderWidget),
                        ]
                    )
                } else {
                    textContent = placeholderWidget
                }
            } else if let placeholderText = textBox.placeholderText {
                if isFocused && !textBox.readOnly {
                    // Caret AND placeholder, the way every platform's search
                    // box behaves: focusing the field used to blank the hint,
                    // which on a box that autofocuses meant the hint was never
                    // readable at all.
                    textContent = Row(
                        mainAxisSize: .min,
                        children: [
                            Text(caretGlyph, style: effectiveTextStyle),
                            Expanded(child: Text(placeholderText,
                                                 style: placeholderStyle,
                                                 overflow: .clip, maxLines: 1)),
                        ]
                    )
                } else {
                    textContent = Text(placeholderText, style: placeholderStyle)
                }
            } else {
                if isFocused && !textBox.readOnly {
                    textContent = Text(caretGlyph, style: effectiveTextStyle)
                } else {
                    textContent = SizedBox(width: 0, height: 0)
                }
            }
        } else {
            textContent = Text(
                textWithCursor,
                style: effectiveTextStyle,
                overflow: .clip,
                maxLines: textBox.maxLines
            )
        }

        // Build the inner row with optional prefix/suffix
        var rowChildren: [Widget] = []
        if let prefix = textBox.prefix {
            rowChildren.append(prefix)
            rowChildren.append(SizedBox(width: 8))
        }
        rowChildren.append(Expanded(child: textContent))
        if let suffix = textBox.suffix {
            rowChildren.append(SizedBox(width: 8))
            rowChildren.append(suffix)
        }

        let innerRow: Widget = Row(
            mainAxisSize: .max,
            crossAxisAlignment: .center,
            children: rowChildren
        )

        let paddedContent: Widget = Padding(
            padding: effectivePadding,
            child: innerRow
        )

        return HoverButton(
            builder: { [self] context, states in
                // Resolve background and border decoration
                let bgColor: Color
                let borderColor: Color
                let borderWidth: Double

                if !isEnabled {
                    bgColor = theme.resources.controlFillColorDisabled
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                } else if isFocused {
                    bgColor = theme.resources.controlFillColorInputActive
                    borderColor = theme.accentColor.defaultBrushFor(theme.brightness)
                    borderWidth = 2.0
                } else if states.isHovered {
                    bgColor = theme.resources.controlFillColorSecondary
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                } else {
                    bgColor = theme.resources.controlFillColorDefault
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                }

                let effectiveDecoration: BoxDecoration
                if isFocused, let focusedDec = textBox.focusedDecoration {
                    effectiveDecoration = focusedDec
                } else if let baseDec = textBox.decoration {
                    effectiveDecoration = baseDec
                } else {
                    effectiveDecoration = BoxDecoration(
                        color: bgColor,
                        border: Border.all(color: borderColor, width: borderWidth),
                        borderRadius: BorderRadius.circular(4)
                    )
                }

                let decorated: Widget = _TextBoxDecoratedBox(
                    decoration: effectiveDecoration,
                    child: paddedContent
                )

                return FocusBorder(
                    child: decorated,
                    focused: isFocused && textBox.showFocusRing
                )
            },
            onPressed: isEnabled
                ? { [self] in
                    _focusNode.requestFocus()
                    _effectiveController.moveCursorToEnd()
                }
                : nil,
            forceEnabled: isEnabled
        )
    }
}

// MARK: - _TextBoxDecoratedBox

/// A widget that paints a `BoxDecoration` behind its child.
class _TextBoxDecoratedBox: SingleChildRenderObjectWidget {
    let decoration: BoxDecoration

    init(
        key: (any Key)? = nil,
        decoration: BoxDecoration,
        child: Widget? = nil
    ) {
        self.decoration = decoration
        super.init(key: key, child: child)
    }

    override func createRenderObject(_ context: any BuildContext) -> RenderObject {
        return RenderDecoratedBox(decoration: decoration)
    }

    override func updateRenderObject(_ context: any BuildContext, renderObject: RenderObject) {
        let ro = renderObject as! RenderDecoratedBox
        ro.decoration = decoration
    }
}

// MARK: - TextBoxTheme

/// An inherited theme that controls how descendant TextBoxes look.
public class TextBoxTheme: InheritedTheme {
    /// The theme data for the text box theme.
    public let data: TextBoxThemeData

    public init(key: (any Key)? = nil, data: TextBoxThemeData, child: Widget) {
        self.data = data
        super.init(key: key, child: child)
    }

    /// Returns the closest TextBoxThemeData which encloses the given context.
    public static func of(_ context: any BuildContext) -> TextBoxThemeData {
        let theme = FluentTheme.of(context)
        let inherited = context.dependOnInheritedWidgetOfExactType(TextBoxTheme.self)
        return TextBoxThemeData.standard(theme).merge(inherited?.data)
    }

    public override func updateShouldNotify(_ oldWidget: InheritedWidget) -> Bool {
        guard let old = oldWidget as? TextBoxTheme else { return true }
        return data !== old.data
    }

    public override func wrap(_ context: any BuildContext, _ child: Widget) -> Widget {
        return TextBoxTheme(data: data, child: child)
    }
}

// MARK: - TextBoxThemeData

/// Theme data for TextBox widgets.
public class TextBoxThemeData {
    /// The decoration of the text box in its default state.
    public let decoration: (any WidgetStateProperty<BoxDecoration?>)?

    /// The padding inside the text box.
    public let padding: EdgeInsets?

    /// The margin around the text box.
    public let margin: EdgeInsets?

    /// The foreground/text color.
    public let foregroundColor: (any WidgetStateProperty<Color?>)?

    /// The placeholder text color.
    public let placeholderColor: Color?

    /// The cursor color.
    public let cursorColor: Color?

    public init(
        decoration: (any WidgetStateProperty<BoxDecoration?>)? = nil,
        padding: EdgeInsets? = nil,
        margin: EdgeInsets? = nil,
        foregroundColor: (any WidgetStateProperty<Color?>)? = nil,
        placeholderColor: Color? = nil,
        cursorColor: Color? = nil
    ) {
        self.decoration = decoration
        self.padding = padding
        self.margin = margin
        self.foregroundColor = foregroundColor
        self.placeholderColor = placeholderColor
        self.cursorColor = cursorColor
    }

    /// Creates the standard TextBoxThemeData based on the given theme.
    public static func standard(_ theme: FluentThemeData) -> TextBoxThemeData {
        return TextBoxThemeData(
            decoration: WidgetStatePropertyHelper.resolveWith({ states -> BoxDecoration? in
                let bgColor: Color
                let borderColor: Color
                let borderWidth: Double

                if states.isDisabled {
                    bgColor = theme.resources.controlFillColorDisabled
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                } else if states.isFocused {
                    bgColor = theme.resources.controlFillColorInputActive
                    borderColor = theme.accentColor.defaultBrushFor(theme.brightness)
                    borderWidth = 2.0
                } else if states.isHovered {
                    bgColor = theme.resources.controlFillColorSecondary
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                } else {
                    bgColor = theme.resources.controlFillColorDefault
                    borderColor = theme.resources.controlStrokeColorDefault
                    borderWidth = 1.0
                }

                return BoxDecoration(
                    color: bgColor,
                    border: Border.all(color: borderColor, width: borderWidth),
                    borderRadius: BorderRadius.circular(4)
                )
            }),
            padding: EdgeInsets(left: 10, top: 5, right: 10, bottom: 7),
            foregroundColor: WidgetStatePropertyHelper.resolveWith({ states -> Color? in
                states.isDisabled ? theme.resources.textFillColorDisabled : theme.resources.textFillColorPrimary
            }),
            placeholderColor: theme.resources.textFillColorSecondary,
            cursorColor: theme.resources.textFillColorPrimary
        )
    }

    /// Merge this theme data with another, with the other taking precedence.
    public func merge(_ other: TextBoxThemeData?) -> TextBoxThemeData {
        guard let other = other else { return self }
        return TextBoxThemeData(
            decoration: other.decoration ?? decoration,
            padding: other.padding ?? padding,
            margin: other.margin ?? margin,
            foregroundColor: other.foregroundColor ?? foregroundColor,
            placeholderColor: other.placeholderColor ?? placeholderColor,
            cursorColor: other.cursorColor ?? cursorColor
        )
    }
}
