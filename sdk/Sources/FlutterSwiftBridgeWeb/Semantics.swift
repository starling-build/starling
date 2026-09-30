// Semantics, which skwasm knows nothing about: it is a renderer, and the
// accessibility tree on the web is DOM (ARIA roles on elements the page
// owns). These classes are therefore plain Swift. They accept everything the
// framework sends and keep only what a caller can read back.
//
// WEB-TODO: a DOM/ARIA semantics tree. The builder would have to retain the
// nodes it is given and UpdateViewSemantics hand them to the page, which
// needs host functions that do not exist yet.

extension flutter.swift_bridge {

    // MARK: - SemanticsFlagsBridge

    public final class SemanticsFlagsBridge {
        // The seven tristates are enum raw values, as in the C++ class:
        // isChecked is SemanticsCheckState (0 none, 1 true, 2 false, 3 mixed),
        // the rest SemanticsTristate (0 none, 1 true, 2 false).
        private let isChecked: Int32
        private let isSelected: Int32
        private let isEnabled: Int32
        private let isToggled: Int32
        private let isExpanded: Int32
        private let isRequired: Int32
        private let isFocused: Int32

        private let isButton: Bool
        private let isTextField: Bool
        private let isInMutuallyExclusiveGroup: Bool
        private let isHeader: Bool
        private let isObscured: Bool
        private let scopesRoute: Bool
        private let namesRoute: Bool
        private let isHidden: Bool
        private let isImage: Bool
        private let isLiveRegion: Bool
        private let hasImplicitScrolling: Bool
        private let isMultiline: Bool
        private let isReadOnly: Bool
        private let isLink: Bool
        private let isSlider: Bool
        private let isKeyboardKey: Bool

        public init(
            _ isChecked: Int32,
            _ isSelected: Int32,
            _ isEnabled: Int32,
            _ isToggled: Int32,
            _ isExpanded: Int32,
            _ isRequired: Int32,
            _ isFocused: Int32,
            _ isButton: Bool,
            _ isTextField: Bool,
            _ isInMutuallyExclusiveGroup: Bool,
            _ isHeader: Bool,
            _ isObscured: Bool,
            _ scopesRoute: Bool,
            _ namesRoute: Bool,
            _ isHidden: Bool,
            _ isImage: Bool,
            _ isLiveRegion: Bool,
            _ hasImplicitScrolling: Bool,
            _ isMultiline: Bool,
            _ isReadOnly: Bool,
            _ isLink: Bool,
            _ isSlider: Bool,
            _ isKeyboardKey: Bool
        ) {
            self.isChecked = isChecked
            self.isSelected = isSelected
            self.isEnabled = isEnabled
            self.isToggled = isToggled
            self.isExpanded = isExpanded
            self.isRequired = isRequired
            self.isFocused = isFocused
            self.isButton = isButton
            self.isTextField = isTextField
            self.isInMutuallyExclusiveGroup = isInMutuallyExclusiveGroup
            self.isHeader = isHeader
            self.isObscured = isObscured
            self.scopesRoute = scopesRoute
            self.namesRoute = namesRoute
            self.isHidden = isHidden
            self.isImage = isImage
            self.isLiveRegion = isLiveRegion
            self.hasImplicitScrolling = hasImplicitScrolling
            self.isMultiline = isMultiline
            self.isReadOnly = isReadOnly
            self.isLink = isLink
            self.isSlider = isSlider
            self.isKeyboardKey = isKeyboardKey
        }

        public func GetIsChecked() -> Int32 { isChecked }
        public func GetIsSelected() -> Int32 { isSelected }
        public func GetIsEnabled() -> Int32 { isEnabled }
        public func GetIsToggled() -> Int32 { isToggled }
        public func GetIsExpanded() -> Int32 { isExpanded }
        public func GetIsRequired() -> Int32 { isRequired }
        public func GetIsFocused() -> Int32 { isFocused }

        public func GetIsButton() -> Bool { isButton }
        public func GetIsTextField() -> Bool { isTextField }
        public func GetIsInMutuallyExclusiveGroup() -> Bool { isInMutuallyExclusiveGroup }
        public func GetIsHeader() -> Bool { isHeader }
        public func GetIsObscured() -> Bool { isObscured }
        public func GetScopesRoute() -> Bool { scopesRoute }
        public func GetNamesRoute() -> Bool { namesRoute }
        public func GetIsHidden() -> Bool { isHidden }
        public func GetIsImage() -> Bool { isImage }
        public func GetIsLiveRegion() -> Bool { isLiveRegion }
        public func GetHasImplicitScrolling() -> Bool { hasImplicitScrolling }
        public func GetIsMultiline() -> Bool { isMultiline }
        public func GetIsReadOnly() -> Bool { isReadOnly }
        public func GetIsLink() -> Bool { isLink }
        public func GetIsSlider() -> Bool { isSlider }
        public func GetIsKeyboardKey() -> Bool { isKeyboardKey }
    }

    // MARK: - String attributes

    public final class SpellOutStringAttributeBridge {
        private let start: Int32
        private let end: Int32

        public init(_ start: Int32, _ end: Int32) {
            self.start = start
            self.end = end
        }

        public func GetStart() -> Int32 { start }
        public func GetEnd() -> Int32 { end }
    }

    public final class LocaleStringAttributeBridge {
        private let start: Int32
        private let end: Int32
        /// NUL-terminated and owned by us: GetLocale hands out a pointer that
        /// has to stay valid for as long as this object does, which the
        /// constructor's argument (a withCString temporary) does not.
        private let locale: UnsafeMutablePointer<CChar>

        public init(_ start: Int32, _ end: Int32, _ locale: UnsafePointer<CChar>?) {
            self.start = start
            self.end = end
            self.locale = copyCString(locale)
        }

        deinit { locale.deallocate() }

        public func GetStart() -> Int32 { start }
        public func GetEnd() -> Int32 { end }
        public func GetLocale() -> UnsafePointer<CChar>? { UnsafePointer(locale) }
    }

    // MARK: - SemanticsUpdateBridge

    public final class SemanticsUpdateBridge {
        /// What the builder had been given when it built this, for anyone
        /// debugging "is the framework sending semantics at all".
        public let nodeCount: Int32
        public let customActionCount: Int32

        public init(nodeCount: Int32 = 0, customActionCount: Int32 = 0) {
            self.nodeCount = nodeCount
            self.customActionCount = customActionCount
        }

        /// The C++ constructor's shape. There is nothing behind either
        /// pointer here, so they are ignored.
        public init(_ opaque_nodes: UnsafeMutableRawPointer?, _ opaque_actions: UnsafeMutableRawPointer?) {
            self.nodeCount = 0
            self.customActionCount = 0
        }

        /// Nothing is held, so there is nothing to release.
        public func Dispose() {}

        // WEB-TODO: no node or action storage exists to point at.
        public func GetNodesPtr() -> UnsafeRawPointer? { nil }
        public func GetActionsPtr() -> UnsafeRawPointer? { nil }
    }

    // MARK: - SemanticsUpdateBuilderBridge

    public final class SemanticsUpdateBuilderBridge {
        // Counts only. Every pointer argument below is a temporary of the
        // caller's (withCString, withUnsafeBufferPointer, strdup'd locales it
        // frees on return), so keeping any of them would be keeping garbage.
        private var nodeCount: Int32 = 0
        private var customActionCount: Int32 = 0

        public init() {}

        // WEB-TODO: the node is dropped. A DOM semantics tree would copy the
        // strings and arrays out here, before the caller's buffers go away.
        public func UpdateNode(
            _ id: Int32,
            _ flags_bridge: SemanticsFlagsBridge?,
            _ actions: Int32,
            _ max_value_length: Int32,
            _ current_value_length: Int32,
            _ text_selection_base: Int32,
            _ text_selection_extent: Int32,
            _ platform_view_id: Int32,
            _ scroll_children: Int32,
            _ scroll_index: Int32,
            _ scroll_position: Double,
            _ scroll_extent_max: Double,
            _ scroll_extent_min: Double,
            _ left: Double,
            _ top: Double,
            _ right: Double,
            _ bottom: Double,
            _ identifier: UnsafePointer<CChar>?,
            _ label: UnsafePointer<CChar>?,
            _ label_attribute_count: Int32,
            _ label_attribute_types: UnsafePointer<Int32>?,
            _ label_attribute_starts: UnsafePointer<Int32>?,
            _ label_attribute_ends: UnsafePointer<Int32>?,
            _ label_attribute_locales: UnsafePointer<UnsafePointer<CChar>?>?,
            _ value: UnsafePointer<CChar>?,
            _ value_attribute_count: Int32,
            _ value_attribute_types: UnsafePointer<Int32>?,
            _ value_attribute_starts: UnsafePointer<Int32>?,
            _ value_attribute_ends: UnsafePointer<Int32>?,
            _ value_attribute_locales: UnsafePointer<UnsafePointer<CChar>?>?,
            _ increased_value: UnsafePointer<CChar>?,
            _ increased_value_attribute_count: Int32,
            _ increased_value_attribute_types: UnsafePointer<Int32>?,
            _ increased_value_attribute_starts: UnsafePointer<Int32>?,
            _ increased_value_attribute_ends: UnsafePointer<Int32>?,
            _ increased_value_attribute_locales: UnsafePointer<UnsafePointer<CChar>?>?,
            _ decreased_value: UnsafePointer<CChar>?,
            _ decreased_value_attribute_count: Int32,
            _ decreased_value_attribute_types: UnsafePointer<Int32>?,
            _ decreased_value_attribute_starts: UnsafePointer<Int32>?,
            _ decreased_value_attribute_ends: UnsafePointer<Int32>?,
            _ decreased_value_attribute_locales: UnsafePointer<UnsafePointer<CChar>?>?,
            _ hint: UnsafePointer<CChar>?,
            _ hint_attribute_count: Int32,
            _ hint_attribute_types: UnsafePointer<Int32>?,
            _ hint_attribute_starts: UnsafePointer<Int32>?,
            _ hint_attribute_ends: UnsafePointer<Int32>?,
            _ hint_attribute_locales: UnsafePointer<UnsafePointer<CChar>?>?,
            _ tooltip: UnsafePointer<CChar>?,
            _ text_direction: Int32,
            _ transform: UnsafePointer<Double>?,
            _ transform_length: Int32,
            _ children_in_traversal_order: UnsafePointer<Int32>?,
            _ children_in_traversal_order_length: Int32,
            _ children_in_hit_test_order: UnsafePointer<Int32>?,
            _ children_in_hit_test_order_length: Int32,
            _ additional_actions: UnsafePointer<Int32>?,
            _ additional_actions_length: Int32,
            _ heading_level: Int32,
            _ link_url: UnsafePointer<CChar>?,
            _ role: Int32,
            _ controls_nodes: UnsafePointer<CChar>?,
            _ has_controls_nodes: Bool,
            _ validation_result: Int32,
            _ input_type: Int32,
            _ locale: UnsafePointer<CChar>?
        ) {
            nodeCount &+= 1
        }

        // WEB-TODO: dropped, as UpdateNode.
        public func UpdateCustomAction(
            _ id: Int32,
            _ label: UnsafePointer<CChar>?,
            _ hint: UnsafePointer<CChar>?,
            _ override_id: Int32
        ) {
            customActionCount &+= 1
        }

        /// Optional because the C++ one returns a pointer; never nil here.
        public func Build() -> SemanticsUpdateBridge? {
            let update = SemanticsUpdateBridge(
                nodeCount: nodeCount, customActionCount: customActionCount)
            nodeCount = 0
            customActionCount = 0
            return update
        }
    }

    // MARK: - view_bridge.h

    // WEB-TODO: hand the update to the page's semantics tree. Until one
    // exists this is the same no-op the native function is without an engine
    // callback registered.
    public static func UpdateViewSemantics(
        _ view_id: Int64, _ update_bridge: SemanticsUpdateBridge?
    ) {}
}

/// A heap copy of a C string, NUL included; an empty string for nil. Free
/// with `deallocate()`. Spelled out rather than strdup so this module needs
/// no libc import.
func copyCString(_ source: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar> {
    var length = 0
    if let source {
        while source[length] != 0 { length += 1 }
    }
    let copy = UnsafeMutablePointer<CChar>.allocate(capacity: length + 1)
    if let source, length > 0 {
        copy.update(from: source, count: length)
    }
    copy[length] = 0
    return copy
}
