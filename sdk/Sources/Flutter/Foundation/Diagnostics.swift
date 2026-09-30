// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

/// Diagnostics library providing tools for debugging and inspecting Flutter objects.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`

// MARK: - DiagnosticLevel

/// The various priority levels used to filter which diagnostics are shown and omitted.
///
/// Trees of Flutter diagnostics can be very large so filtering the diagnostics
/// shown matters. Typically filtering to only show diagnostics with at least
/// level `debug` is appropriate.
///
/// In release mode, this level may not have any effect, as diagnostics in
/// release mode are compacted or truncated to reduce binary size.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 63-124
public enum DiagnosticLevel: Int, Comparable, Sendable {
    /// Diagnostics that should not be shown.
    ///
    /// If a user chooses to display `hidden` diagnostics, they should not expect
    /// the diagnostics to be formatted consistently with other diagnostics and
    /// they should expect them to sometimes be misleading. For example,
    /// `FlagProperty` and `ObjectFlagProperty` have uglier formatting when the
    /// property `value` does not match a value with a custom flag
    /// description. An example of a misleading diagnostic is a diagnostic for
    /// a property that has no effect because some other property of the object is
    /// set in a way that causes the hidden property to have no effect.
    ///
    /// **Dart Source:** `diagnostics.dart:64-74`
    case hidden = 0

    /// A diagnostic that is likely to be low value but where the diagnostic
    /// display is just as high quality as a diagnostic with a higher level.
    ///
    /// Use this level for diagnostic properties that match their default value
    /// and other cases where showing a diagnostic would not add much value such
    /// as an `IterableProperty` where the value is empty.
    ///
    /// **Dart Source:** `diagnostics.dart:76-82`
    case fine = 1

    /// Diagnostics that should only be shown when performing fine grained
    /// debugging of an object.
    ///
    /// Unlike a `fine` diagnostic, these diagnostics provide important
    /// information about the object that is likely to be needed to debug. Used by
    /// properties that are important but where the property value is too verbose
    /// (e.g. 300+ characters long) to show with a higher diagnostic level.
    ///
    /// **Dart Source:** `diagnostics.dart:84-91`
    case debug = 2

    /// Interesting diagnostics that should be typically shown.
    ///
    /// **Dart Source:** `diagnostics.dart:93-94`
    case info = 3

    /// Very important diagnostics that indicate problematic property values.
    ///
    /// For example, use if you would write the property description
    /// message in ALL CAPS.
    ///
    /// **Dart Source:** `diagnostics.dart:96-100`
    case warning = 4

    /// Diagnostics that provide a hint about best practices.
    ///
    /// For example, a diagnostic describing best practices for fixing an error.
    ///
    /// **Dart Source:** `diagnostics.dart:102-105`
    case hint = 5

    /// Diagnostics that summarize other diagnostics present.
    ///
    /// For example, use this level for a short one or two line summary
    /// describing other diagnostics present.
    ///
    /// **Dart Source:** `diagnostics.dart:107-111`
    case summary = 6

    /// Diagnostics that indicate errors or unexpected conditions.
    ///
    /// For example, use for property values where computing the value throws an
    /// exception.
    ///
    /// **Dart Source:** `diagnostics.dart:113-117`
    case error = 7

    /// Special level indicating that no diagnostics should be shown.
    ///
    /// Do not specify this level for diagnostics. This level is only used to
    /// filter which diagnostics are shown.
    ///
    /// **Dart Source:** `diagnostics.dart:119-123`
    case off = 8

    // MARK: - Comparable

    public static func < (lhs: DiagnosticLevel, rhs: DiagnosticLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - DiagnosticsTreeStyle

/// Styles for displaying a node in a `DiagnosticsNode` tree.
///
/// In release mode, these styles may be ignored, as diagnostics are compacted
/// or truncated to save on binary size.
///
/// See also:
///
///  * `DiagnosticsNode.toStringDeep`, which dumps text art trees for these
///    styles.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 126-220
public enum DiagnosticsTreeStyle: Sendable {
    /// A style that does not display the tree, for release mode.
    ///
    /// **Dart Source:** `diagnostics.dart:137`
    case none

    /// Sparse style for displaying trees.
    ///
    /// See also:
    ///
    ///  * `RenderObject`, which uses this style.
    ///
    /// **Dart Source:** `diagnostics.dart:139-144`
    case sparse

    /// Connects a node to its parent with a dashed line.
    ///
    /// See also:
    ///
    ///  * `RenderSliverMultiBoxAdaptor`, which uses this style to distinguish
    ///    offstage children from onstage children.
    ///
    /// **Dart Source:** `diagnostics.dart:146-152`
    case offstage

    /// Slightly more compact version of the `sparse` style.
    ///
    /// See also:
    ///
    ///  * `Element`, which uses this style.
    ///
    /// **Dart Source:** `diagnostics.dart:154-159`
    case dense

    /// Style that enables transitioning from nodes of one style to children of
    /// another.
    ///
    /// See also:
    ///
    ///  * `RenderParagraph`, which uses this style to display a `TextSpan` child
    ///    in a way that is compatible with the `DiagnosticsTreeStyle.sparse`
    ///    style of the `RenderObject` tree.
    ///
    /// **Dart Source:** `diagnostics.dart:161-169`
    case transition

    /// Style for displaying content describing an error.
    ///
    /// See also:
    ///
    ///  * `FlutterError`, which uses this style for the root node in a tree
    ///    describing an error.
    ///
    /// **Dart Source:** `diagnostics.dart:171-177`
    case error

    /// Render the tree just using whitespace without connecting parents to
    /// children using lines.
    ///
    /// See also:
    ///
    ///  * `SliverGeometry`, which uses this style.
    ///
    /// **Dart Source:** `diagnostics.dart:179-185`
    case whitespace

    /// Render the tree without indenting children at all.
    ///
    /// See also:
    ///
    ///  * `DiagnosticsStackTrace`, which uses this style.
    ///
    /// **Dart Source:** `diagnostics.dart:187-192`
    case flat

    /// Render the tree on a single line without showing children.
    ///
    /// **Dart Source:** `diagnostics.dart:194-195`
    case singleLine

    /// Render the tree using a style appropriate for properties that are part
    /// of an error message.
    ///
    /// The name is placed on one line with the value and properties placed on
    /// the following line.
    ///
    /// See also:
    ///
    ///  * `singleLine`, which displays the same information but keeps the
    ///    property and value on the same line.
    ///
    /// **Dart Source:** `diagnostics.dart:197-207`
    case errorProperty

    /// Render only the immediate properties of a node instead of the full tree.
    ///
    /// See also:
    ///
    ///  * `DebugOverflowIndicatorMixin`, which uses this style to display just
    ///    the immediate children of a node.
    ///
    /// **Dart Source:** `diagnostics.dart:209-215`
    case shallow

    /// Render only the children of a node truncating before the tree becomes too
    /// large.
    ///
    /// **Dart Source:** `diagnostics.dart:217-219`
    case truncateChildren
}

// MARK: - TextTreeConfiguration

/// Configuration specifying how a particular `DiagnosticsTreeStyle` should be
/// rendered as text art.
///
/// In release mode, these configurations may be ignored, as diagnostics are
/// compacted or truncated to save on binary size.
///
/// See also:
///
///  * `sparseTextConfiguration`, which is a typical style.
///  * `transitionTextConfiguration`, which is an example of a complex tree style.
///  * `DiagnosticsNode.toStringDeep`, for code using `TextTreeConfiguration`
///    to render text art for arbitrary trees of `DiagnosticsNode` objects.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 222-391
public struct TextTreeConfiguration: Sendable {
    /// Prefix to add to the first line to display a child with this style.
    ///
    /// **Dart Source:** `diagnostics.dart:264-265`
    public let prefixLineOne: String

    /// Suffix to add to end of the first line to make its length match the footer.
    ///
    /// **Dart Source:** `diagnostics.dart:267-268`
    public let suffixLineOne: String

    /// Prefix to add to other lines to display a child with this style.
    ///
    /// `prefixOtherLines` should typically be one character shorter than
    /// `prefixLineOne` is.
    ///
    /// **Dart Source:** `diagnostics.dart:270-274`
    public let prefixOtherLines: String

    /// Prefix to add to the first line to display the last child of a node with
    /// this style.
    ///
    /// **Dart Source:** `diagnostics.dart:276-278`
    public let prefixLastChildLineOne: String

    /// Additional prefix to add to other lines of a node if this is the root node
    /// of the tree.
    ///
    /// **Dart Source:** `diagnostics.dart:280-282`
    public let prefixOtherLinesRootNode: String

    /// Prefix to add before each property if the node has children.
    ///
    /// Plays a similar role to `linkCharacter` except that some configurations
    /// intentionally use a different line style than the `linkCharacter`.
    ///
    /// **Dart Source:** `diagnostics.dart:284-288`
    public let propertyPrefixIfChildren: String

    /// Prefix to add before each property if the node does not have children.
    ///
    /// This string is typically a whitespace string the same length as
    /// `propertyPrefixIfChildren` but can have a different length.
    ///
    /// **Dart Source:** `diagnostics.dart:290-294`
    public let propertyPrefixNoChildren: String

    /// Character to use to draw line linking parent to child.
    ///
    /// The first child does not require a line but all subsequent children do
    /// with the line drawn immediately before the left edge of the previous
    /// sibling.
    ///
    /// **Dart Source:** `diagnostics.dart:296-301`
    public let linkCharacter: String

    /// Whitespace to draw instead of the childLink character if this node is the
    /// last child of its parent so no link line is required.
    ///
    /// **Dart Source:** `diagnostics.dart:303-305`
    public let childLinkSpace: String

    /// Character(s) to use to separate lines.
    ///
    /// Typically leave set at the default value of '\\n' unless this style needs
    /// to treat lines differently as is the case for
    /// `singleLineTextConfiguration`.
    ///
    /// **Dart Source:** `diagnostics.dart:307-312`
    public let lineBreak: String

    /// Whether to place line breaks between properties or to leave all
    /// properties on one line.
    ///
    /// **Dart Source:** `diagnostics.dart:314-316`
    public let lineBreakProperties: Bool

    /// Text added immediately before the name of the node.
    ///
    /// See `errorTextConfiguration` for an example of using this to achieve a
    /// custom line art style.
    ///
    /// **Dart Source:** `diagnostics.dart:318-322`
    public let beforeName: String

    /// Text added immediately after the name of the node.
    ///
    /// See `transitionTextConfiguration` for an example of using a value other
    /// than ':' to achieve a custom line art style.
    ///
    /// **Dart Source:** `diagnostics.dart:324-328`
    public let afterName: String

    /// Text to add immediately after the description line of a node with
    /// properties and/or children if the node has a body.
    ///
    /// **Dart Source:** `diagnostics.dart:330-332`
    public let afterDescriptionIfBody: String

    /// Text to add immediately after the description line of a node with
    /// properties and/or children.
    ///
    /// **Dart Source:** `diagnostics.dart:334-336`
    public let afterDescription: String

    /// Optional string to add before the properties of a node.
    ///
    /// Only displayed if the node has properties.
    /// See `singleLineTextConfiguration` for an example of using this field
    /// to enclose the property list with parenthesis.
    ///
    /// **Dart Source:** `diagnostics.dart:338-343`
    public let beforeProperties: String

    /// Optional string to add after the properties of a node.
    ///
    /// See documentation for `beforeProperties`.
    ///
    /// **Dart Source:** `diagnostics.dart:345-348`
    public let afterProperties: String

    /// Mandatory string to add after the properties of a node regardless of
    /// whether the node has any properties.
    ///
    /// **Dart Source:** `diagnostics.dart:350-352`
    public let mandatoryAfterProperties: String

    /// Property separator to add between properties.
    ///
    /// See `singleLineTextConfiguration` for an example of using this field
    /// to render properties as a comma separated list.
    ///
    /// **Dart Source:** `diagnostics.dart:354-358`
    public let propertySeparator: String

    /// Prefix to add to all lines of the body of the tree node.
    ///
    /// The body is all content in the node other than the name and description.
    ///
    /// **Dart Source:** `diagnostics.dart:360-363`
    public let bodyIndent: String

    /// Whether the children of a node should be shown.
    ///
    /// See `singleLineTextConfiguration` for an example of using this field to
    /// hide all children of a node.
    ///
    /// **Dart Source:** `diagnostics.dart:365-369`
    public let showChildren: Bool

    /// Whether to add a blank line at the end of the output for a node if it has
    /// no children.
    ///
    /// See `denseTextConfiguration` for an example of setting this to false.
    ///
    /// **Dart Source:** `diagnostics.dart:371-375`
    public let addBlankLineIfNoChildren: Bool

    /// Whether the name should be displayed on the same line as the description.
    ///
    /// **Dart Source:** `diagnostics.dart:377-378`
    public let isNameOnOwnLine: Bool

    /// Footer to add as its own line at the end of a non-root node.
    ///
    /// See `transitionTextConfiguration` for an example of using footer to draw a box
    /// around the node. `footer` is indented the same amount as `prefixOtherLines`.
    ///
    /// **Dart Source:** `diagnostics.dart:380-384`
    public let footer: String

    /// Footer to add even for root nodes.
    ///
    /// **Dart Source:** `diagnostics.dart:386-387`
    public let mandatoryFooter: String

    /// Add a blank line between properties and children if both are present.
    ///
    /// **Dart Source:** `diagnostics.dart:389-390`
    public let isBlankLineBetweenPropertiesAndChildren: Bool

    /// Create a configuration object describing how to render a tree as text.
    ///
    /// **Dart Source:** `diagnostics.dart:235-262`
    public init(
        prefixLineOne: String,
        prefixOtherLines: String,
        prefixLastChildLineOne: String,
        prefixOtherLinesRootNode: String,
        linkCharacter: String,
        propertyPrefixIfChildren: String,
        propertyPrefixNoChildren: String,
        lineBreak: String = "\n",
        lineBreakProperties: Bool = true,
        afterName: String = ":",
        afterDescriptionIfBody: String = "",
        afterDescription: String = "",
        beforeProperties: String = "",
        afterProperties: String = "",
        mandatoryAfterProperties: String = "",
        propertySeparator: String = "",
        bodyIndent: String = "",
        footer: String = "",
        showChildren: Bool = true,
        addBlankLineIfNoChildren: Bool = true,
        isNameOnOwnLine: Bool = false,
        isBlankLineBetweenPropertiesAndChildren: Bool = true,
        beforeName: String = "",
        suffixLineOne: String = "",
        mandatoryFooter: String = ""
    ) {
        self.prefixLineOne = prefixLineOne
        self.prefixOtherLines = prefixOtherLines
        self.prefixLastChildLineOne = prefixLastChildLineOne
        self.prefixOtherLinesRootNode = prefixOtherLinesRootNode
        self.linkCharacter = linkCharacter
        self.propertyPrefixIfChildren = propertyPrefixIfChildren
        self.propertyPrefixNoChildren = propertyPrefixNoChildren
        self.lineBreak = lineBreak
        self.lineBreakProperties = lineBreakProperties
        self.afterName = afterName
        self.afterDescriptionIfBody = afterDescriptionIfBody
        self.afterDescription = afterDescription
        self.beforeProperties = beforeProperties
        self.afterProperties = afterProperties
        self.mandatoryAfterProperties = mandatoryAfterProperties
        self.propertySeparator = propertySeparator
        self.bodyIndent = bodyIndent
        self.footer = footer
        self.showChildren = showChildren
        self.addBlankLineIfNoChildren = addBlankLineIfNoChildren
        self.isNameOnOwnLine = isNameOnOwnLine
        self.isBlankLineBetweenPropertiesAndChildren = isBlankLineBetweenPropertiesAndChildren
        self.beforeName = beforeName
        self.suffixLineOne = suffixLineOne
        self.mandatoryFooter = mandatoryFooter
        // childLinkSpace is computed as spaces with the same length as linkCharacter
        self.childLinkSpace = String(repeating: " ", count: linkCharacter.count)
    }
}

// MARK: - Pre-defined Text Configurations

/// Default text tree configuration.
///
/// Example:
///
///     <root_name>: <root_description>
///      │ <property1>
///      │ <property2>
///      │ ...
///      │ <propertyN>
///      ├─<child_name>: <child_description>
///      │ │ <property1>
///      │ │ <property2>
///      │ │ ...
///      │ │ <propertyN>
///      │ │
///      │ └─<child_name>: <child_description>
///      │     <property1>
///      │     <property2>
///      │     ...
///      │     <propertyN>
///      │
///      └─<child_name>: <child_description>'
///        <property1>
///        <property2>
///        ...
///        <propertyN>
///
/// See also:
///
///  * `DiagnosticsTreeStyle.sparse`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:393-431`
public let sparseTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "├─",
    prefixOtherLines: " ",
    prefixLastChildLineOne: "└─",
    prefixOtherLinesRootNode: " ",
    linkCharacter: "│",
    propertyPrefixIfChildren: "│ ",
    propertyPrefixNoChildren: "  "
)

/// Identical to `sparseTextConfiguration` except that the lines connecting
/// parent to children are dashed.
///
/// Example:
///
///     <root_name>: <root_description>
///      │ <property1>
///      │ <property2>
///      │ ...
///      │ <propertyN>
///      ├─<normal_child_name>: <child_description>
///      ╎ │ <property1>
///      ╎ │ <property2>
///      ╎ │ ...
///      ╎ │ <propertyN>
///      ╎ │
///      ╎ └─<child_name>: <child_description>
///      ╎     <property1>
///      ╎     <property2>
///      ╎     ...
///      ╎     <propertyN>
///      ╎
///      ╎╌<dashed_child_name>: <child_description>
///      ╎ │ <property1>
///      ╎ │ <property2>
///      ╎ │ ...
///      ╎ │ <propertyN>
///      ╎ │
///      ╎ └─<child_name>: <child_description>
///      ╎     <property1>
///      ╎     <property2>
///      ╎     ...
///      ╎     <propertyN>
///      ╎
///      └╌<dashed_child_name>: <child_description>'
///        <property1>
///        <property2>
///        ...
///        <propertyN>
///
/// See also:
///
///  * `DiagnosticsTreeStyle.offstage`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:433-486`
public let dashedTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "╎╌",
    prefixOtherLines: " ",
    prefixLastChildLineOne: "└╌",
    prefixOtherLinesRootNode: " ",
    linkCharacter: "╎",
    // Intentionally not set as a dashed line as that would make the properties
    // look like they were disabled.
    propertyPrefixIfChildren: "│ ",
    propertyPrefixNoChildren: "  "
)

/// Dense text tree configuration that minimizes horizontal whitespace.
///
/// Example:
///
///     <root_name>: <root_description>(<property1>; <property2> <propertyN>)
///     ├<child_name>: <child_description>(<property1>, <property2>, <propertyN>)
///     └<child_name>: <child_description>(<property1>, <property2>, <propertyN>)
///
/// See also:
///
///  * `DiagnosticsTreeStyle.dense`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:488-513`
public let denseTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "├",
    prefixOtherLines: "",
    prefixLastChildLineOne: "└",
    prefixOtherLinesRootNode: "",
    linkCharacter: "│",
    propertyPrefixIfChildren: "│",
    propertyPrefixNoChildren: " ",
    lineBreakProperties: false,
    beforeProperties: "(",
    afterProperties: ")",
    propertySeparator: ", ",
    addBlankLineIfNoChildren: false,
    isBlankLineBetweenPropertiesAndChildren: false
)

/// Configuration that draws a box around a leaf node.
///
/// Used by leaf nodes such as `TextSpan` to draw a clear border around the
/// contents of a node.
///
/// Example:
///
///     <parent_node>
///     ╞═╦══ <name> ═══
///     │ ║  <description>:
///     │ ║    <body>
///     │ ║    ...
///     │ ╚═══════════
///     ╘═╦══ <name> ═══
///       ║  <description>:
///       ║    <body>
///       ║    ...
///       ╚═══════════
///
/// See also:
///
///  * `DiagnosticsTreeStyle.transition`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:515-561`
public let transitionTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "╞═╦══ ",
    prefixOtherLines: " ║ ",
    prefixLastChildLineOne: "╘═╦══ ",
    prefixOtherLinesRootNode: "",
    linkCharacter: "│",
    // Subtree boundaries are clear due to the border around the node so omit the
    // property prefix.
    propertyPrefixIfChildren: "",
    propertyPrefixNoChildren: "",
    afterName: " ═══",
    // Add a colon after the description if the node has a body to make the
    // connection between the description and the body clearer.
    afterDescriptionIfBody: ":",
    // Members are indented an extra two spaces to disambiguate as the description
    // is placed within the box instead of along side the name as is the case for
    // other styles.
    bodyIndent: "  ",
    footer: " ╚═══════════",
    // No need to add a blank line as the footer makes the boundary of this
    // subtree unambiguous.
    addBlankLineIfNoChildren: false,
    isNameOnOwnLine: true,
    isBlankLineBetweenPropertiesAndChildren: false
)

/// Configuration that draws a box around a node ignoring the connection to the
/// parents.
///
/// If nested in a tree, this node is best displayed in the property box rather
/// than as a traditional child.
///
/// Used to draw a decorative box around detailed descriptions of an exception.
///
/// Example:
///
///     ══╡ <name>: <description> ╞═════════════════════════════════════
///     <body>
///     ...
///     ├─<normal_child_name>: <child_description>
///     ╎ │ <property1>
///     ╎ │ <property2>
///     ╎ │ ...
///     ╎ │ <propertyN>
///     ╎ │
///     ╎ └─<child_name>: <child_description>
///     ╎     <property1>
///     ╎     <property2>
///     ╎     ...
///     ╎     <propertyN>
///     ╎
///     ╎╌<dashed_child_name>: <child_description>
///     ╎ │ <property1>
///     ╎ │ <property2>
///     ╎ │ ...
///     ╎ │ <propertyN>
///     ╎ │
///     ╎ └─<child_name>: <child_description>
///     ╎     <property1>
///     ╎     <property2>
///     ╎     ...
///     ╎     <propertyN>
///     ╎
///     └╌<dashed_child_name>: <child_description>'
///     ════════════════════════════════════════════════════════════════
///
/// See also:
///
///  * `DiagnosticsTreeStyle.error`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:563-624`
public let errorTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "╞═╦",
    prefixOtherLines: " ║ ",
    prefixLastChildLineOne: "╘═╦",
    prefixOtherLinesRootNode: "",
    linkCharacter: "│",
    // Subtree boundaries are clear due to the border around the node so omit the
    // property prefix.
    propertyPrefixIfChildren: "",
    propertyPrefixNoChildren: "",
    footer: " ╚═══════════",
    // No need to add a blank line as the footer makes the boundary of this
    // subtree unambiguous.
    addBlankLineIfNoChildren: false,
    isBlankLineBetweenPropertiesAndChildren: false,
    beforeName: "══╡ ",
    suffixLineOne: " ╞══",
    mandatoryFooter: "═════"
)

/// Whitespace only configuration where children are consistently indented
/// two spaces.
///
/// Use this style for displaying properties with structured values or for
/// displaying children within a `transitionTextConfiguration` as using a style that
/// draws line art would be visually distracting for those cases.
///
/// Example:
///
///     <parent_node>
///       <name>: <description>:
///         <properties>
///         <children>
///       <name>: <description>:
///         <properties>
///         <children>
///
/// See also:
///
///  * `DiagnosticsTreeStyle.whitespace`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:626-659`
public let whitespaceTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "",
    prefixOtherLines: " ",
    prefixLastChildLineOne: "",
    prefixOtherLinesRootNode: "  ",
    linkCharacter: " ",
    propertyPrefixIfChildren: "",
    propertyPrefixNoChildren: "",
    // Add a colon after the description and before the properties to link the
    // properties to the description line.
    afterDescriptionIfBody: ":",
    addBlankLineIfNoChildren: false,
    isBlankLineBetweenPropertiesAndChildren: false
)

/// Whitespace only configuration where children are not indented.
///
/// Use this style when indentation is not needed to disambiguate parents from
/// children as in the case of a `DiagnosticsStackTrace`.
///
/// Example:
///
///     <parent_node>
///     <name>: <description>:
///     <properties>
///     <children>
///     <name>: <description>:
///     <properties>
///     <children>
///
/// See also:
///
///  * `DiagnosticsTreeStyle.flat`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:661-692`
public let flatTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "",
    prefixOtherLines: "",
    prefixLastChildLineOne: "",
    prefixOtherLinesRootNode: "",
    linkCharacter: "",
    propertyPrefixIfChildren: "",
    propertyPrefixNoChildren: "",
    // Add a colon after the description and before the properties to link the
    // properties to the description line.
    afterDescriptionIfBody: ":",
    addBlankLineIfNoChildren: false,
    isBlankLineBetweenPropertiesAndChildren: false
)

/// Render a node as a single line omitting children.
///
/// Example:
/// `<name>: <description>(<property1>, <property2>, ..., <propertyN>)`
///
/// See also:
///
///  * `DiagnosticsTreeStyle.singleLine`, uses this style for ASCII art display.
///
/// **Dart Source:** `diagnostics.dart:694-717`
public let singleLineTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "",
    prefixOtherLines: "",
    prefixLastChildLineOne: "",
    prefixOtherLinesRootNode: "",
    linkCharacter: "",
    propertyPrefixIfChildren: "  ",
    propertyPrefixNoChildren: "  ",
    lineBreak: "",
    lineBreakProperties: false,
    beforeProperties: "(",
    afterProperties: ")",
    propertySeparator: ", ",
    showChildren: false,
    addBlankLineIfNoChildren: false
)

/// Render the name on a line followed by the body and properties on the next
/// line omitting the children.
///
/// Example:
///
///     <name>:
///       <description>(<property1>, <property2>, ..., <propertyN>)
///
/// See also:
///
///  * `DiagnosticsTreeStyle.errorProperty`, uses this style for ASCII art
///    display.
///
/// **Dart Source:** `diagnostics.dart:719-746`
public let errorPropertyTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "",
    prefixOtherLines: "",
    prefixLastChildLineOne: "",
    prefixOtherLinesRootNode: "",
    linkCharacter: "",
    propertyPrefixIfChildren: "  ",
    propertyPrefixNoChildren: "  ",
    lineBreakProperties: false,
    beforeProperties: "(",
    afterProperties: ")",
    propertySeparator: ", ",
    showChildren: false,
    addBlankLineIfNoChildren: false,
    isNameOnOwnLine: true
)

/// Render a node on multiple lines omitting children.
///
/// Example:
/// `<name>: <description>
///   <property1>
///   <property2>
///   <propertyN>`
///
/// See also:
///
///  * `DiagnosticsTreeStyle.shallow`
///
/// **Dart Source:** `diagnostics.dart:748-773`
public let shallowTextConfiguration = TextTreeConfiguration(
    prefixLineOne: "",
    prefixOtherLines: " ",
    prefixLastChildLineOne: "",
    prefixOtherLinesRootNode: "  ",
    linkCharacter: " ",
    propertyPrefixIfChildren: "",
    propertyPrefixNoChildren: "",
    // Add a colon after the description and before the properties to link the
    // properties to the description line.
    afterDescriptionIfBody: ":",
    showChildren: false,
    addBlankLineIfNoChildren: false,
    isBlankLineBetweenPropertiesAndChildren: false
)

// MARK: - Internal Word Wrap Parse Mode

/// Internal enum for word wrap parsing state machine.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 775
enum WordWrapParseMode {
    case inSpace
    case inWord
    case atBreak
}

// MARK: - Prefixed String Builder

/// Builder that builds a String with specified prefixes for the first and
/// subsequent lines.
///
/// Allows for the incremental building of strings using `write*()` methods.
/// The strings are concatenated into a single string with the first line
/// prefixed by `prefixLineOne` and subsequent lines prefixed by
/// `prefixOtherLines`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 777-1065
final class PrefixedStringBuilder {
    /// Creates a prefixed string builder with specified prefixes.
    ///
    /// **Dart Source:** `diagnostics.dart:784-789`
    init(
        prefixLineOne: String,
        prefixOtherLines: String?,
        wrapWidth: Int?
    ) {
        self.prefixLineOne = prefixLineOne
        self._prefixOtherLines = prefixOtherLines
        self.wrapWidth = wrapWidth
    }

    /// Prefix to add to the first line.
    ///
    /// **Dart Source:** `diagnostics.dart:791-792`
    let prefixLineOne: String

    /// Prefix to add to subsequent lines.
    ///
    /// The prefix can be modified while the string is being built in which case
    /// subsequent lines will be added with the modified prefix.
    ///
    /// **Dart Source:** `diagnostics.dart:794-803`
    var prefixOtherLines: String? {
        get { _nextPrefixOtherLines ?? _prefixOtherLines }
        set {
            _prefixOtherLines = newValue
            _nextPrefixOtherLines = nil
        }
    }
    private var _prefixOtherLines: String?

    private var _nextPrefixOtherLines: String?

    /// Increment the prefix for other lines.
    ///
    /// **Dart Source:** `diagnostics.dart:806-813`
    func incrementPrefixOtherLines(_ suffix: String, updateCurrentLine: Bool) {
        if _currentLine.isEmpty || updateCurrentLine {
            _prefixOtherLines = (prefixOtherLines ?? "") + suffix
            _nextPrefixOtherLines = nil
        } else {
            _nextPrefixOtherLines = (prefixOtherLines ?? "") + suffix
        }
    }

    /// The wrap width for text wrapping.
    ///
    /// **Dart Source:** `diagnostics.dart:815`
    let wrapWidth: Int?

    /// Buffer containing lines that have already been completely laid out.
    ///
    /// **Dart Source:** `diagnostics.dart:817-818`
    private var _buffer: String = ""

    /// Buffer containing the current line that has not yet been wrapped.
    ///
    /// **Dart Source:** `diagnostics.dart:820-821`
    private var _currentLine: String = ""

    /// List of pairs of integers indicating the start and end of each block of
    /// text within _currentLine that can be wrapped.
    ///
    /// **Dart Source:** `diagnostics.dart:823-825`
    private var _wrappableRanges: [Int] = []

    /// Whether the string being built already has more than 1 line.
    ///
    /// **Dart Source:** `diagnostics.dart:827-831`
    var requiresMultipleLines: Bool {
        _numLines > 1 ||
        (_numLines == 1 && !_currentLine.isEmpty) ||
        (_currentLine.count + (getCurrentPrefix(firstLine: true) ?? "").count > (wrapWidth ?? Int.max))
    }

    /// Whether the current line is empty.
    ///
    /// **Dart Source:** `diagnostics.dart:833`
    var isCurrentLineEmpty: Bool { _currentLine.isEmpty }

    private var _numLines = 0

    /// Finalizes the current line by applying word wrapping if needed.
    ///
    /// **Dart Source:** `diagnostics.dart:837-861`
    private func finalizeLine(_ addTrailingLineBreak: Bool) {
        let firstLine = _buffer.isEmpty
        let text = _currentLine
        _currentLine = ""

        if _wrappableRanges.isEmpty {
            // Fast path. There were no wrappable spans of text.
            writeLine(text, includeLineBreak: addTrailingLineBreak, firstLine: firstLine)
            return
        }
        let lines = PrefixedStringBuilder.wordWrapLine(
            text,
            wrapRanges: _wrappableRanges,
            width: wrapWidth!,
            startOffset: firstLine ? prefixLineOne.count : (_prefixOtherLines ?? "").count,
            otherLineOffset: (_prefixOtherLines ?? "").count
        )
        var i = 0
        let length = lines.count
        for line in lines {
            i += 1
            writeLine(line, includeLineBreak: addTrailingLineBreak || i < length, firstLine: firstLine)
        }
        _wrappableRanges.removeAll()
    }

    /// Wraps the given string at the given width.
    ///
    /// Wrapping occurs at space characters (U+0020).
    ///
    /// This is not suitable for use with arbitrary Unicode text. For example, it
    /// doesn't implement UAX #14, can't handle ideographic text, doesn't hyphenate,
    /// and so forth. It is only intended for formatting error messages.
    ///
    /// This method wraps a sequence of text where only some spans of text can be
    /// used as wrap boundaries.
    ///
    /// **Dart Source:** `diagnostics.dart:863-965`
    static func wordWrapLine(
        _ message: String,
        wrapRanges: [Int],
        width: Int,
        startOffset: Int = 0,
        otherLineOffset: Int = 0
    ) -> [String] {
        if message.count + startOffset < width {
            // Nothing to do. The line doesn't wrap.
            return [message]
        }

        var wrappedLine: [String] = []
        var startForLengthCalculations = -startOffset
        var addPrefix = false
        var index = 0
        var mode = WordWrapParseMode.inSpace
        var lastWordStart = 0
        var lastWordEnd: Int?
        var start = 0

        var currentChunk = 0
        let messageArray = Array(message)

        // This helper is called with increasing indexes.
        func noWrap(_ index: Int) -> Bool {
            while true {
                if currentChunk >= wrapRanges.count {
                    return true
                }
                if index < wrapRanges[currentChunk + 1] {
                    break // Found nearest chunk.
                }
                currentChunk += 2
            }
            return index < wrapRanges[currentChunk]
        }

        while true {
            switch mode {
            case .inSpace: // at start of break point (or start of line); can't break until next break
                while index < messageArray.count && messageArray[index] == " " {
                    index += 1
                }
                lastWordStart = index
                mode = .inWord
            case .inWord: // looking for a good break point. Treat all text
                while index < messageArray.count && (messageArray[index] != " " || noWrap(index)) {
                    index += 1
                }
                mode = .atBreak
            case .atBreak: // at start of break point
                if (index - startForLengthCalculations > width) || (index == messageArray.count) {
                    // we are over the width line, so break
                    if (index - startForLengthCalculations <= width) || (lastWordEnd == nil) {
                        // we should use this point, because either it doesn't actually go over the
                        // end (last line), or it does, but there was no earlier break point
                        lastWordEnd = index
                    }
                    let line = String(messageArray[start..<lastWordEnd!])
                    wrappedLine.append(line)
                    addPrefix = true
                    if lastWordEnd! >= messageArray.count {
                        return wrappedLine
                    }
                    // just yielded a line
                    if lastWordEnd == index {
                        // we broke at current position
                        // eat all the wrappable spaces, then set our start point
                        // Even if some of the spaces are not wrappable that is ok.
                        while index < messageArray.count && messageArray[index] == " " {
                            index += 1
                        }
                        start = index
                        mode = .inWord
                    } else {
                        // we broke at the previous break point, and we're at the start of a new one
                        assert(lastWordStart > lastWordEnd!)
                        start = lastWordStart
                        mode = .atBreak
                    }
                    startForLengthCalculations = start - otherLineOffset
                    assert(addPrefix)
                    lastWordEnd = nil
                } else {
                    // save this break point, we're not yet over the line width
                    lastWordEnd = index
                    // skip to the end of this break point
                    mode = .inSpace
                }
            }
        }
    }

    /// Write text ensuring the specified prefixes for the first and subsequent
    /// lines.
    ///
    /// If `allowWrap` is true, the text may be wrapped to stay within the
    /// allow `wrapWidth`.
    ///
    /// **Dart Source:** `diagnostics.dart:967-1000`
    func write(_ s: String, allowWrap: Bool = false) {
        if s.isEmpty {
            return
        }

        let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        for (i, line) in lines.enumerated() {
            if i > 0 {
                finalizeLine(true)
                updatePrefix()
            }
            let lineStr = String(line)
            if !lineStr.isEmpty {
                if allowWrap && wrapWidth != nil {
                    let wrapStart = _currentLine.count
                    let wrapEnd = wrapStart + lineStr.count
                    if let lastRange = _wrappableRanges.last, lastRange == wrapStart {
                        // Extend last range.
                        _wrappableRanges[_wrappableRanges.count - 1] = wrapEnd
                    } else {
                        _wrappableRanges.append(wrapStart)
                        _wrappableRanges.append(wrapEnd)
                    }
                }
                _currentLine += lineStr
            }
        }
    }

    /// Updates the prefix for other lines.
    ///
    /// **Dart Source:** `diagnostics.dart:1002-1007`
    private func updatePrefix() {
        if _nextPrefixOtherLines != nil {
            _prefixOtherLines = _nextPrefixOtherLines
            _nextPrefixOtherLines = nil
        }
    }

    /// Writes a single line with the appropriate prefix.
    ///
    /// **Dart Source:** `diagnostics.dart:1009-1016`
    private func writeLine(_ line: String, includeLineBreak: Bool, firstLine: Bool) {
        var fullLine = (getCurrentPrefix(firstLine: firstLine) ?? "") + line
        // Trim trailing whitespace
        while fullLine.hasSuffix(" ") {
            fullLine.removeLast()
        }
        _buffer += fullLine
        if includeLineBreak {
            _buffer += "\n"
        }
        _numLines += 1
    }

    /// Returns the current prefix based on whether this is the first line.
    ///
    /// **Dart Source:** `diagnostics.dart:1018-1020`
    private func getCurrentPrefix(firstLine: Bool) -> String? {
        return _buffer.isEmpty ? prefixLineOne : _prefixOtherLines
    }

    /// Write lines assuming the lines obey the specified prefixes. Ensures that
    /// a newline is added if one is not present.
    ///
    /// **Dart Source:** `diagnostics.dart:1022-1040`
    func writeRawLines(_ lines: String) {
        if lines.isEmpty {
            return
        }

        if !_currentLine.isEmpty {
            finalizeLine(true)
        }
        assert(_currentLine.isEmpty)

        _buffer += lines
        if !lines.hasSuffix("\n") {
            _buffer += "\n"
        }
        _numLines += 1
        updatePrefix()
    }

    /// Finishes the current line with a stretched version of text.
    ///
    /// **Dart Source:** `diagnostics.dart:1042-1056`
    func writeStretched(_ text: String, targetLineLength: Int) {
        write(text)
        let currentLineLength = _currentLine.count + (getCurrentPrefix(firstLine: _buffer.isEmpty) ?? "").count
        assert(_currentLine.count > 0)
        let targetLength = targetLineLength - currentLineLength
        if targetLength > 0 {
            assert(!text.isEmpty)
            let lastChar = text.last!
            assert(lastChar != "\n")
            _currentLine += String(repeating: lastChar, count: targetLength)
        }
        // Mark the entire line as not wrappable.
        _wrappableRanges.removeAll()
    }

    /// Builds the final string from all written content.
    ///
    /// **Dart Source:** `diagnostics.dart:1058-1064`
    func build() -> String {
        if !_currentLine.isEmpty {
            finalizeLine(false)
        }
        return _buffer
    }
}

// MARK: - No Default Value

/// Marker type indicating that a `DiagnosticsNode` has no default value.
///
/// This type is used as a sentinel to distinguish "no default value provided"
/// from "nil is the default value". Use `isNoDefaultValue(_:)` to check if
/// a value is the no-default-value marker.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1067-1069
public struct NoDefaultValue: Sendable, Equatable {
    fileprivate init() {}
}

/// Marker object indicating that a `DiagnosticsNode` has no default value.
///
/// Use `isNoDefaultValue(_:)` to check if a value matches this marker.
///
/// **Dart Source:** `diagnostics.dart:1071-1072`
public let kNoDefaultValue = NoDefaultValue()

/// Checks if the given value is the no-default-value marker.
///
/// Returns `true` if `value` is `kNoDefaultValue`.
public func isNoDefaultValue<T>(_ value: T) -> Bool {
    if let noDefault = value as? NoDefaultValue {
        return noDefault == kNoDefaultValue
    }
    return false
}

// MARK: - Single Line Helper

/// Returns true if the given style should render on a single line.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1074-1076
func isSingleLine(_ style: DiagnosticsTreeStyle?) -> Bool {
    return style == .singleLine
}

// MARK: - DiagnosticsNode Protocol

/// Protocol defining the interface for diagnostics data for a value.
///
/// For debug and profile modes, `DiagnosticsNode` provides a high quality
/// multiline string dump via `toStringDeep`. The core members are the `name`,
/// `toDescription`, `getProperties`, `value`, and `getChildren`. All other
/// members exist typically to provide hints for how `toStringDeep` and
/// debugging tools should format output.
///
/// In release mode, far less information is retained and some information may
/// not print at all.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1467-1893
public protocol DiagnosticsNodeProtocol: AnyObject {
    /// Label describing the `DiagnosticsNode`, typically shown before a separator.
    ///
    /// The name will be omitted if the `showName` property is false.
    ///
    /// **Dart Source:** `diagnostics.dart:1512-1516`
    var name: String? { get }

    /// Returns a description with a short summary of the node itself not
    /// including children or properties.
    ///
    /// `parentConfiguration` specifies how the parent is rendered as text art.
    ///
    /// **Dart Source:** `diagnostics.dart:1518-1524`
    func toDescription(parentConfiguration: TextTreeConfiguration?) -> String

    /// Whether to show a separator between `name` and description.
    ///
    /// **Dart Source:** `diagnostics.dart:1526-1530`
    var showSeparator: Bool { get }

    /// Whether the diagnostic should be filtered due to its `level` being lower
    /// than `minLevel`.
    ///
    /// **Dart Source:** `diagnostics.dart:1532-1537`
    func isFiltered(_ minLevel: DiagnosticLevel) -> Bool

    /// Priority level of the diagnostic used to control which diagnostics should
    /// be shown and filtered.
    ///
    /// **Dart Source:** `diagnostics.dart:1539-1548`
    var level: DiagnosticLevel { get }

    /// Whether the name of the property should be shown when showing the default
    /// view of the tree.
    ///
    /// **Dart Source:** `diagnostics.dart:1550-1555`
    var showName: Bool { get }

    /// Prefix to include at the start of each line.
    ///
    /// **Dart Source:** `diagnostics.dart:1557-1558`
    var linePrefix: String? { get }

    /// Description to show if the node has no displayed properties or children.
    ///
    /// **Dart Source:** `diagnostics.dart:1560-1561`
    var emptyBodyDescription: String? { get }

    /// The actual object this is diagnostics data for.
    ///
    /// **Dart Source:** `diagnostics.dart:1563-1564`
    var value: Any? { get }

    /// Hint for how the node should be displayed.
    ///
    /// **Dart Source:** `diagnostics.dart:1566-1567`
    var style: DiagnosticsTreeStyle? { get }

    /// Whether to wrap text on onto multiple lines or not.
    ///
    /// **Dart Source:** `diagnostics.dart:1569-1570`
    var allowWrap: Bool { get }

    /// Whether to wrap the name onto multiple lines or not.
    ///
    /// **Dart Source:** `diagnostics.dart:1572-1573`
    var allowNameWrap: Bool { get }

    /// Whether to allow truncation when displaying the node and its children.
    ///
    /// **Dart Source:** `diagnostics.dart:1575-1576`
    var allowTruncate: Bool { get }

    /// Properties of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:1578-1582`
    func getProperties() -> [any DiagnosticsNodeProtocol]

    /// Children of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:1584-1590`
    func getChildren() -> [any DiagnosticsNodeProtocol]

    /// Returns a configuration specifying how this object should be rendered
    /// as text art.
    ///
    /// **Dart Source:** `diagnostics.dart:1764-1786`
    var textTreeConfiguration: TextTreeConfiguration? { get }
}

/// Default implementations for `DiagnosticsNodeProtocol`.
public extension DiagnosticsNodeProtocol {
    /// Default implementation returns false.
    var allowWrap: Bool { false }

    /// Default implementation returns false.
    var allowNameWrap: Bool { false }

    /// Default implementation returns false.
    var allowTruncate: Bool { false }

    /// Default implementation returns nil.
    var emptyBodyDescription: String? { nil }

    /// Whether the diagnostic should be filtered due to its `level` being lower
    /// than `minLevel`.
    ///
    /// **Dart Source:** `diagnostics.dart:1532-1537`
    func isFiltered(_ minLevel: DiagnosticLevel) -> Bool {
        #if !DEBUG
        return true
        #else
        return level.rawValue < minLevel.rawValue
        #endif
    }

    /// Returns the text tree configuration for the node's style.
    ///
    /// **Dart Source:** `diagnostics.dart:1764-1786`
    var textTreeConfiguration: TextTreeConfiguration? {
        guard let style = style else { return nil }
        switch style {
        case .none:
            return nil
        case .dense:
            return denseTextConfiguration
        case .sparse:
            return sparseTextConfiguration
        case .offstage:
            return dashedTextConfiguration
        case .whitespace:
            return whitespaceTextConfiguration
        case .transition:
            return transitionTextConfiguration
        case .singleLine:
            return singleLineTextConfiguration
        case .errorProperty:
            return errorPropertyTextConfiguration
        case .shallow:
            return shallowTextConfiguration
        case .error:
            return errorTextConfiguration
        case .flat:
            return flatTextConfiguration
        case .truncateChildren:
            return whitespaceTextConfiguration
        }
    }
}

// MARK: - TextTreeRenderer

/// Renderer that creates ASCII art representations of trees of
/// `DiagnosticsNode` objects.
///
/// See also:
///
///  * `DiagnosticsNode.toStringDeep`, which uses a `TextTreeRenderer` to return a
///    string representation of this node and its descendants.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1078-1445
public class TextTreeRenderer {
    /// Creates a `TextTreeRenderer` object with the given arguments specifying
    /// how the tree is rendered.
    ///
    /// Lines are wrapped to at the maximum of `wrapWidth` and the current indent
    /// plus `wrapWidthProperties` characters. This ensures that wrapping does not
    /// become too excessive when displaying very deep trees and that wrapping
    /// only occurs at the overall `wrapWidth` when the tree is not very indented.
    /// If `maxDescendentsTruncatableNode` is specified, `DiagnosticsNode` objects
    /// with `allowTruncate` set to `true` are truncated after including
    /// `maxDescendentsTruncatableNode` descendants of the node to be truncated.
    ///
    /// **Dart Source:** `diagnostics.dart:1086-1104`
    public init(
        minLevel: DiagnosticLevel = .debug,
        wrapWidth: Int = 100,
        wrapWidthProperties: Int = 65,
        maxDescendentsTruncatableNode: Int = -1
    ) {
        self._minLevel = minLevel
        self._wrapWidth = wrapWidth
        self._wrapWidthProperties = wrapWidthProperties
        self._maxDescendentsTruncatableNode = maxDescendentsTruncatableNode
    }

    private let _wrapWidth: Int
    private let _wrapWidthProperties: Int
    private let _minLevel: DiagnosticLevel
    private let _maxDescendentsTruncatableNode: Int

    /// Text configuration to use to connect this node to a `child`.
    ///
    /// The singleLine styles are special cased because the connection from the
    /// parent to the child should be consistent with the parent's style as the
    /// single line style does not provide any meaningful style for how children
    /// should be connected to their parents.
    ///
    /// **Dart Source:** `diagnostics.dart:1111-1125`
    private func childTextConfiguration(
        _ child: any DiagnosticsNodeProtocol,
        _ textStyle: TextTreeConfiguration
    ) -> TextTreeConfiguration? {
        let childStyle = child.style
        return (isSingleLine(childStyle) || childStyle == .errorProperty)
            ? textStyle
            : child.textTreeConfiguration
    }

    /// Renders a `node` to a String.
    ///
    /// **Dart Source:** `diagnostics.dart:1127-1144`
    public func render(
        _ node: any DiagnosticsNodeProtocol,
        prefixLineOne: String = "",
        prefixOtherLines: String? = nil,
        parentConfiguration: TextTreeConfiguration? = nil
    ) -> String {
        #if !DEBUG
        return ""
        #else
        return debugRender(
            node,
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            parentConfiguration: parentConfiguration
        )
        #endif
    }

    /// Internal render implementation for debug mode.
    ///
    /// **Dart Source:** `diagnostics.dart:1146-1444`
    private func debugRender(
        _ node: any DiagnosticsNodeProtocol,
        prefixLineOne: String = "",
        prefixOtherLines: String? = nil,
        parentConfiguration: TextTreeConfiguration? = nil
    ) -> String {
        var prefixLineOne = prefixLineOne
        var prefixOtherLines = prefixOtherLines ?? prefixLineOne

        let nodeSingleLine = isSingleLine(node.style) && parentConfiguration?.lineBreakProperties != true

        if let linePrefix = node.linePrefix {
            prefixLineOne += linePrefix
            prefixOtherLines += linePrefix
        }

        guard let config = node.textTreeConfiguration else {
            return ""
        }

        if prefixOtherLines.isEmpty {
            prefixOtherLines += config.prefixOtherLinesRootNode
        }

        if node.style == .truncateChildren {
            // This style is different enough that it isn't worthwhile to reuse the
            // existing logic.
            return renderTruncateChildren(node, prefixLineOne: prefixLineOne, prefixOtherLines: prefixOtherLines)
        }

        let builder = PrefixedStringBuilder(
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            wrapWidth: max(_wrapWidth, prefixOtherLines.count + _wrapWidthProperties)
        )

        var children = node.getChildren()

        var description = node.toDescription(parentConfiguration: parentConfiguration)
        if !config.beforeName.isEmpty {
            builder.write(config.beforeName)
        }
        let wrapName = !nodeSingleLine && node.allowNameWrap
        let wrapDescription = !nodeSingleLine && node.allowWrap
        let uppercaseTitle = node.style == .error
        var name = node.name
        if uppercaseTitle {
            name = name?.uppercased()
        }
        if description.isEmpty {
            if node.showName && name != nil {
                builder.write(name!, allowWrap: wrapName)
            }
        } else {
            var includeName = false
            if let name = name, !name.isEmpty, node.showName {
                includeName = true
                builder.write(name, allowWrap: wrapName)
                if node.showSeparator {
                    builder.write(config.afterName, allowWrap: wrapName)
                }

                builder.write(
                    config.isNameOnOwnLine || description.contains(Character("\n")) ? "\n" : " ",
                    allowWrap: wrapName
                )
            }
            if !nodeSingleLine && builder.requiresMultipleLines && !builder.isCurrentLineEmpty {
                // Make sure there is a break between the current line and next one if
                // there is not one already.
                builder.write("\n")
            }
            if includeName {
                builder.incrementPrefixOtherLines(
                    children.isEmpty ? config.propertyPrefixNoChildren : config.propertyPrefixIfChildren,
                    updateCurrentLine: true
                )
            }

            if uppercaseTitle {
                description = description.uppercased()
            }
            // trimRight equivalent - remove trailing whitespace
            var rightTrimmed = description
            while rightTrimmed.hasSuffix(" ") || rightTrimmed.hasSuffix("\t") {
                rightTrimmed.removeLast()
            }
            builder.write(rightTrimmed, allowWrap: wrapDescription)

            if !includeName {
                builder.incrementPrefixOtherLines(
                    children.isEmpty ? config.propertyPrefixNoChildren : config.propertyPrefixIfChildren,
                    updateCurrentLine: false
                )
            }
        }
        if !config.suffixLineOne.isEmpty {
            builder.writeStretched(config.suffixLineOne, targetLineLength: builder.wrapWidth!)
        }

        let propertiesIterable = node.getProperties().filter { n in
            !n.isFiltered(_minLevel)
        }
        var properties: [any DiagnosticsNodeProtocol]
        if _maxDescendentsTruncatableNode >= 0 && node.allowTruncate {
            if propertiesIterable.count < _maxDescendentsTruncatableNode {
                properties = Array(propertiesIterable.prefix(_maxDescendentsTruncatableNode))
                properties.append(DiagnosticsMessage("..."))
            } else {
                properties = propertiesIterable
            }
            if _maxDescendentsTruncatableNode < children.count {
                children = Array(children.prefix(_maxDescendentsTruncatableNode))
                children.append(DiagnosticsMessage("..."))
            }
        } else {
            properties = propertiesIterable
        }

        // If the node does not show a separator and there is no description then
        // we should not place a separator between the name and the value.
        // Essentially in this case the properties are treated a bit like a value.
        if (!properties.isEmpty || !children.isEmpty || node.emptyBodyDescription != nil) &&
            (node.showSeparator || !description.isEmpty) {
            builder.write(config.afterDescriptionIfBody)
        }

        if config.lineBreakProperties {
            builder.write(config.lineBreak)
        }

        if !properties.isEmpty {
            builder.write(config.beforeProperties)
        }

        builder.incrementPrefixOtherLines(config.bodyIndent, updateCurrentLine: false)

        if let emptyBodyDescription = node.emptyBodyDescription,
           properties.isEmpty && children.isEmpty && !prefixLineOne.isEmpty {
            builder.write(emptyBodyDescription)
            if config.lineBreakProperties {
                builder.write(config.lineBreak)
            }
        }

        for i in 0..<properties.count {
            let property = properties[i]
            if i > 0 {
                builder.write(config.propertySeparator)
            }

            guard let propertyStyle = property.textTreeConfiguration else { continue }
            if isSingleLine(property.style) {
                // We have to treat single line properties slightly differently to deal
                // with cases where a single line properties output may not have single
                // linebreak.
                let propertyRender = render(
                    property,
                    prefixLineOne: propertyStyle.prefixLineOne,
                    prefixOtherLines: "\(propertyStyle.childLinkSpace)\(propertyStyle.prefixOtherLines)",
                    parentConfiguration: config
                )
                let propertyLines = propertyRender.split(separator: "\n", omittingEmptySubsequences: false)
                if propertyLines.count == 1 && !config.lineBreakProperties {
                    builder.write(String(propertyLines.first!))
                } else {
                    builder.write(propertyRender)
                    if !propertyRender.hasSuffix("\n") {
                        builder.write("\n")
                    }
                }
            } else {
                let propertyRender = render(
                    property,
                    prefixLineOne: "\(builder.prefixOtherLines ?? "")\(propertyStyle.prefixLineOne)",
                    prefixOtherLines: "\(builder.prefixOtherLines ?? "")\(propertyStyle.childLinkSpace)\(propertyStyle.prefixOtherLines)",
                    parentConfiguration: config
                )
                builder.writeRawLines(propertyRender)
            }
        }
        if !properties.isEmpty {
            builder.write(config.afterProperties)
        }

        builder.write(config.mandatoryAfterProperties)

        if !config.lineBreakProperties {
            builder.write(config.lineBreak)
        }

        let prefixChildren = config.bodyIndent
        let prefixChildrenRaw = "\(prefixOtherLines)\(prefixChildren)"
        if children.isEmpty &&
            config.addBlankLineIfNoChildren &&
            builder.requiresMultipleLines &&
            !(builder.prefixOtherLines?.trimmingWhitespace(newlines: false).isEmpty ?? true) {
            builder.write(config.lineBreak)
        }

        if !children.isEmpty && config.showChildren {
            if config.isBlankLineBetweenPropertiesAndChildren &&
                !properties.isEmpty &&
                (children.first?.textTreeConfiguration?.isBlankLineBetweenPropertiesAndChildren ?? false) {
                builder.write(config.lineBreak)
            }

            builder.prefixOtherLines = prefixOtherLines

            for i in 0..<children.count {
                let child = children[i]
                guard let childConfig = childTextConfiguration(child, config) else { continue }
                if i == children.count - 1 {
                    let lastChildPrefixLineOne = "\(prefixChildrenRaw)\(childConfig.prefixLastChildLineOne)"
                    let childPrefixOtherLines = "\(prefixChildrenRaw)\(childConfig.childLinkSpace)\(childConfig.prefixOtherLines)"
                    builder.writeRawLines(
                        render(
                            child,
                            prefixLineOne: lastChildPrefixLineOne,
                            prefixOtherLines: childPrefixOtherLines,
                            parentConfiguration: config
                        )
                    )
                    if !childConfig.footer.isEmpty {
                        builder.prefixOtherLines = prefixChildrenRaw
                        builder.write("\(childConfig.childLinkSpace)\(childConfig.footer)")
                        if !childConfig.mandatoryFooter.isEmpty {
                            builder.writeStretched(
                                childConfig.mandatoryFooter,
                                targetLineLength: max(builder.wrapWidth!, _wrapWidthProperties + childPrefixOtherLines.count)
                            )
                        }
                        builder.write(config.lineBreak)
                    }
                } else {
                    guard let nextChildStyle = childTextConfiguration(children[i + 1], config) else { continue }
                    let childPrefixLineOne = "\(prefixChildrenRaw)\(childConfig.prefixLineOne)"
                    let childPrefixOtherLines = "\(prefixChildrenRaw)\(nextChildStyle.linkCharacter)\(childConfig.prefixOtherLines)"
                    builder.writeRawLines(
                        render(
                            child,
                            prefixLineOne: childPrefixLineOne,
                            prefixOtherLines: childPrefixOtherLines,
                            parentConfiguration: config
                        )
                    )
                    if !childConfig.footer.isEmpty {
                        builder.prefixOtherLines = prefixChildrenRaw
                        builder.write("\(childConfig.linkCharacter)\(childConfig.footer)")
                        if !childConfig.mandatoryFooter.isEmpty {
                            builder.writeStretched(
                                childConfig.mandatoryFooter,
                                targetLineLength: max(builder.wrapWidth!, _wrapWidthProperties + childPrefixOtherLines.count)
                            )
                        }
                        builder.write(config.lineBreak)
                    }
                }
            }
        }
        if parentConfiguration == nil && !config.mandatoryFooter.isEmpty {
            builder.writeStretched(config.mandatoryFooter, targetLineLength: builder.wrapWidth!)
            builder.write(config.lineBreak)
        }
        return builder.build()
    }

    /// Renders a node with truncateChildren style.
    ///
    /// **Dart Source:** `diagnostics.dart:1165-1203`
    private func renderTruncateChildren(
        _ node: any DiagnosticsNodeProtocol,
        prefixLineOne: String,
        prefixOtherLines: String
    ) -> String {
        var descendants: [String] = []
        let maxDepth = 5
        var depth = 0
        let maxLines = 25
        var lines = 0

        func visitor(_ node: any DiagnosticsNodeProtocol) {
            for child in node.getChildren() {
                if lines < maxLines {
                    depth += 1
                    descendants.append("\(prefixOtherLines)\(String(repeating: "  ", count: depth))\(describeNode(child))")
                    if depth < maxDepth {
                        visitor(child)
                    }
                    depth -= 1
                } else if lines == maxLines {
                    descendants.append("\(prefixOtherLines)  ...(descendants list truncated after \(lines) lines)")
                }
                lines += 1
            }
        }

        visitor(node)
        var information = prefixLineOne
        if lines > 1 {
            information += "This \(node.name ?? "node") had the following descendants (showing up to depth \(maxDepth)):\n"
        } else if descendants.count == 1 {
            information += "This \(node.name ?? "node") had the following child:\n"
        } else {
            information += "This \(node.name ?? "node") has no descendants.\n"
        }
        information += descendants.joined(separator: "\n")
        return information
    }

    /// Returns a simple string description of a node for truncated display.
    private func describeNode(_ node: any DiagnosticsNodeProtocol) -> String {
        let description = node.toDescription(parentConfiguration: nil)
        if let name = node.name, !name.isEmpty, node.showName {
            if node.showSeparator {
                return "\(name): \(description)"
            }
            return "\(name) \(description)"
        }
        return description
    }
}

// MARK: - DiagnosticsMessage

/// A simple diagnostics node containing just a message.
///
/// This is a minimal implementation used internally by `TextTreeRenderer`
/// to display truncation messages like "...".
///
/// The full `DiagnosticsNode.message` factory will be implemented in Subtask 7.
///
/// **Dart Source:** `diagnostics.dart:1488-1510`
final class DiagnosticsMessage: DiagnosticsNodeProtocol {
    init(_ message: String, style: DiagnosticsTreeStyle = .singleLine, level: DiagnosticLevel = .info) {
        self._message = message
        self._style = style
        self._level = level
    }

    private let _message: String
    private let _style: DiagnosticsTreeStyle
    private let _level: DiagnosticLevel

    var name: String? { "" }
    var showSeparator: Bool { false }
    var showName: Bool { false }
    var linePrefix: String? { nil }
    var value: Any? { nil }
    var style: DiagnosticsTreeStyle? { _style }
    var level: DiagnosticLevel { _level }

    func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _message
    }

    func getProperties() -> [any DiagnosticsNodeProtocol] { [] }
    func getChildren() -> [any DiagnosticsNodeProtocol] { [] }
}

// MARK: - DiagnosticsNode Base Class

/// Base class providing diagnostics data for a value.
///
/// For debug and profile modes, `DiagnosticsNode` provides a high quality
/// multiline string dump via `toStringDeep`. The core members are the `name`,
/// `toDescription`, `getProperties`, `value`, and `getChildren`. All other
/// members exist typically to provide hints for how `toStringDeep` and
/// debugging tools should format output.
///
/// In release mode, far less information is retained and some information may
/// not print at all.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1467-1893
open class DiagnosticsNode: DiagnosticsNodeProtocol {
    /// Initializes the diagnostics node.
    ///
    /// The `name` should not end with a colon as one will be added automatically
    /// when generating descriptions.
    ///
    /// **Dart Source:** `diagnostics.dart:1472-1486`
    public init(
        name: String?,
        style: DiagnosticsTreeStyle? = nil,
        showName: Bool = true,
        showSeparator: Bool = true,
        linePrefix: String? = nil
    ) {
        // Assert that names don't end with colons
        assert(
            name == nil || !name!.hasSuffix(":"),
            "Names of diagnostic nodes must not end with colons.\nname:\n  \"\(name ?? "")\""
        )
        self._name = name
        self._style = style
        self._showName = showName
        self._showSeparator = showSeparator
        self._linePrefix = linePrefix
    }

    // MARK: - Stored Properties

    private let _name: String?
    private let _style: DiagnosticsTreeStyle?
    private let _showName: Bool
    private let _showSeparator: Bool
    private let _linePrefix: String?

    // MARK: - DiagnosticsNodeProtocol Implementation

    /// Label describing the `DiagnosticsNode`, typically shown before a separator.
    ///
    /// The name will be omitted if the `showName` property is false.
    ///
    /// **Dart Source:** `diagnostics.dart:1512-1516`
    public var name: String? { _name }

    /// Whether to show a separator between `name` and description.
    ///
    /// If false, name and description should be shown with no separation.
    /// `:` is typically used as a separator when displaying as text.
    ///
    /// **Dart Source:** `diagnostics.dart:1526-1530`
    public var showSeparator: Bool { _showSeparator }

    /// Whether the name of the property should be shown when showing the default
    /// view of the tree.
    ///
    /// This could be set to false (hiding the name) if the value's description
    /// will make the name self-evident.
    ///
    /// **Dart Source:** `diagnostics.dart:1550-1555`
    public var showName: Bool { _showName }

    /// Prefix to include at the start of each line.
    ///
    /// **Dart Source:** `diagnostics.dart:1557-1558`
    public var linePrefix: String? { _linePrefix }

    /// Hint for how the node should be displayed.
    ///
    /// **Dart Source:** `diagnostics.dart:1566-1567`
    public var style: DiagnosticsTreeStyle? { _style }

    /// Priority level of the diagnostic used to control which diagnostics should
    /// be shown and filtered.
    ///
    /// Typically this only makes sense to set to a different value than
    /// `DiagnosticLevel.info` for diagnostics representing properties. Some
    /// subclasses have a `level` argument to their constructor which influences
    /// the value returned here but other factors also influence it. For example,
    /// whether an exception is thrown computing a property value
    /// `DiagnosticLevel.error` is returned.
    ///
    /// **Dart Source:** `diagnostics.dart:1539-1548`
    open var level: DiagnosticLevel {
        #if DEBUG
        return .info
        #else
        return .hidden
        #endif
    }

    /// Description to show if the node has no displayed properties or children.
    ///
    /// **Dart Source:** `diagnostics.dart:1560-1561`
    open var emptyBodyDescription: String? { nil }

    /// The actual object this is diagnostics data for.
    ///
    /// **Dart Source:** `diagnostics.dart:1563-1564`
    open var value: Any? { nil }

    /// Whether to wrap text on onto multiple lines or not.
    ///
    /// **Dart Source:** `diagnostics.dart:1569-1570`
    open var allowWrap: Bool { false }

    /// Whether to wrap the name onto multiple lines or not.
    ///
    /// **Dart Source:** `diagnostics.dart:1572-1573`
    open var allowNameWrap: Bool { false }

    /// Whether to allow truncation when displaying the node and its children.
    ///
    /// **Dart Source:** `diagnostics.dart:1575-1576`
    open var allowTruncate: Bool { false }

    /// Returns a description with a short summary of the node itself not
    /// including children or properties.
    ///
    /// `parentConfiguration` specifies how the parent is rendered as text art.
    /// For example, if the parent does not line break between properties, the
    /// description of a property should also be a single line if possible.
    ///
    /// **Dart Source:** `diagnostics.dart:1518-1524`
    open func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        fatalError("Subclasses must implement toDescription(parentConfiguration:)")
    }

    /// Properties of this `DiagnosticsNode`.
    ///
    /// Properties and children are kept distinct even though they are both
    /// `[DiagnosticsNode]` because they should be grouped differently.
    ///
    /// **Dart Source:** `diagnostics.dart:1578-1582`
    open func getProperties() -> [any DiagnosticsNodeProtocol] {
        return []
    }

    /// Children of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:1584-1590`
    open func getChildren() -> [any DiagnosticsNodeProtocol] {
        return []
    }

    // MARK: - Separator

    /// The separator string used between name and description.
    ///
    /// **Dart Source:** `diagnostics.dart:1592`
    private var separator: String {
        return showSeparator ? ":" : ""
    }

    // MARK: - String Representation

    /// Returns a string representation of this diagnostic.
    ///
    /// The representation is compatible with the style of the parent if the node
    /// is not the root.
    ///
    /// `parentConfiguration` specifies how the parent is rendered as text art.
    /// For example, if the parent places all properties on one line, the
    /// `toString` for each property should avoid line breaks if possible.
    ///
    /// `minLevel` specifies the minimum `DiagnosticLevel` for properties included
    /// in the output.
    ///
    /// In release mode, far less information is retained and some information may
    /// not print at all.
    ///
    /// **Dart Source:** `diagnostics.dart:1726-1762`
    public func toString(
        parentConfiguration: TextTreeConfiguration? = nil,
        minLevel: DiagnosticLevel = .info
    ) -> String {
        #if DEBUG
        return debugToString(parentConfiguration: parentConfiguration, minLevel: minLevel)
        #else
        return ""
        #endif
    }

    /// Debug-mode implementation of toString.
    private func debugToString(
        parentConfiguration: TextTreeConfiguration?,
        minLevel: DiagnosticLevel
    ) -> String {
        assert(style != nil)
        if isSingleLine(style) {
            return toStringDeep(parentConfiguration: parentConfiguration, minLevel: minLevel)
        } else {
            let description = toDescription(parentConfiguration: parentConfiguration)

            if name == nil || name!.isEmpty || !showName {
                return description
            }
            return description.contains(Character("\n"))
                ? "\(name!)\(separator)\n\(description)"
                : "\(name!)\(separator) \(description)"
        }
    }

    /// Returns a string representation of this node and its descendants.
    ///
    /// `prefixLineOne` will be added to the front of the first line of the
    /// output. `prefixOtherLines` will be added to the front of each other line.
    /// If `prefixOtherLines` is nil, the `prefixLineOne` is used for every line.
    /// By default, there is no prefix.
    ///
    /// `minLevel` specifies the minimum `DiagnosticLevel` for properties included
    /// in the output.
    ///
    /// `wrapWidth` specifies the column number where word wrapping will be
    /// applied.
    ///
    /// In release mode, far less information is retained and some information may
    /// not print at all.
    ///
    /// **Dart Source:** `diagnostics.dart:1788-1829`
    public func toStringDeep(
        prefixLineOne: String = "",
        prefixOtherLines: String? = nil,
        parentConfiguration: TextTreeConfiguration? = nil,
        minLevel: DiagnosticLevel = .debug,
        wrapWidth: Int = 65
    ) -> String {
        #if DEBUG
        return TextTreeRenderer(minLevel: minLevel, wrapWidth: wrapWidth).render(
            self,
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            parentConfiguration: parentConfiguration
        )
        #else
        return ""
        #endif
    }

    // MARK: - JSON Serialization

    /// Converts the properties of this node to a form useful for Timeline event
    /// arguments.
    ///
    /// Children are omitted.
    ///
    /// This method is only valid in debug builds. In profile builds, this method
    /// throws an error. In release builds it returns nil.
    ///
    /// **Dart Source:** `diagnostics.dart:1594-1629`
    public func toTimelineArguments() -> [String: String]? {
        #if DEBUG
        var result: [String: String] = [:]
        for property in getProperties() {
            if let name = property.name {
                result[name] = property.toDescription(parentConfiguration: singleLineTextConfiguration)
            }
        }
        return result
        #else
        return nil
        #endif
    }

    /// Serialize the node to a JSON map according to the configuration provided
    /// in the serialization delegate.
    ///
    /// Subclasses should override if they have additional properties that are
    /// useful for the GUI tools that consume this JSON.
    ///
    /// **Dart Source:** `diagnostics.dart:1631-1674`
    public func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        #if DEBUG
        let hasChildren = !getChildren().isEmpty
        var result: [String: Any?] = [
            "description": toDescription(parentConfiguration: nil),
            "type": String(describing: Swift.type(of: self)),
        ]

        if let name = name {
            result["name"] = name
        }
        if !showSeparator {
            result["showSeparator"] = showSeparator
        }
        if level != .info {
            result["level"] = String(describing: level)
        }
        if !showName {
            result["showName"] = showName
        }
        if let emptyBodyDescription = emptyBodyDescription {
            result["emptyBodyDescription"] = emptyBodyDescription
        }
        if let style = style, style != .sparse {
            result["style"] = String(describing: style)
        }
        if allowTruncate {
            result["allowTruncate"] = allowTruncate
        }
        if hasChildren {
            result["hasChildren"] = hasChildren
        }
        if let linePrefix = linePrefix, !linePrefix.isEmpty {
            result["linePrefix"] = linePrefix
        }
        if !allowWrap {
            result["allowWrap"] = allowWrap
        }
        if allowNameWrap {
            result["allowNameWrap"] = allowNameWrap
        }

        // Add additional node properties from delegate
        let additionalProperties = delegate.additionalNodeProperties(self)
        for (key, value) in additionalProperties {
            result[key] = value
        }

        if delegate.includeProperties {
            let filteredProperties = delegate.filterProperties(getProperties(), self)
            result["properties"] = DiagnosticsNode.toJsonList(
                filteredProperties,
                parent: self,
                delegate: delegate
            )
        }

        if delegate.subtreeDepth > 0 {
            let filteredChildren = delegate.filterChildren(getChildren(), self)
            result["children"] = DiagnosticsNode.toJsonList(
                filteredChildren,
                parent: self,
                delegate: delegate
            )
        }

        return result
        #else
        return [:]
        #endif
    }

    /// Serializes a list of `DiagnosticsNode`s to a JSON list according to
    /// the configuration provided by the serialization delegate.
    ///
    /// The provided `nodes` may be properties or children of the `parent`
    /// DiagnosticsNode.
    ///
    /// **Dart Source:** `diagnostics.dart:1697-1724`
    public static func toJsonList(
        _ nodes: [any DiagnosticsNodeProtocol]?,
        parent: DiagnosticsNode?,
        delegate: DiagnosticsSerializationDelegate
    ) -> [[String: Any?]] {
        guard var nodes = nodes else {
            return []
        }

        let originalNodeCount = nodes.count
        nodes = delegate.truncateNodesList(nodes, parent)
        var truncated = false
        if nodes.count != originalNodeCount {
            nodes.append(DiagnosticsNode.message("..."))
            truncated = true
        }

        var json: [[String: Any?]] = nodes.map { node in
            if let diagnosticsNode = node as? DiagnosticsNode {
                return diagnosticsNode.toJsonMap(delegate: delegate.delegateForNode(node))
            }
            // Fallback for nodes that aren't DiagnosticsNode subclasses
            return [
                "description": node.toDescription(parentConfiguration: nil),
                "type": String(describing: Swift.type(of: node)),
            ]
        }

        if truncated, !json.isEmpty {
            json[json.count - 1]["truncated"] = true
        }

        return json
    }

    // MARK: - Factory Methods

    /// Diagnostics containing just a string `message` and not a concrete name or
    /// value.
    ///
    /// See also:
    ///
    ///  * `MessageProperty`, which is better suited to messages that are to be
    ///    formatted like a property with a separate name and message.
    ///
    /// **Dart Source:** `diagnostics.dart:1488-1510`
    public static func message(
        _ message: String,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info,
        allowWrap: Bool = true
    ) -> DiagnosticsNode {
        // Note: In Dart, this creates a DiagnosticsProperty<void> with description.
        // Since DiagnosticsProperty will be added in Subtask 8, we use
        // DiagnosticsMessageNode which provides equivalent functionality.
        return DiagnosticsMessageNode(
            message: message,
            style: style,
            level: level,
            allowWrap: allowWrap
        )
    }
}

// MARK: - DiagnosticsMessageNode

/// A diagnostics node that displays a message without a name or value.
///
/// This is the Swift implementation used by `DiagnosticsNode.message()`.
/// In Dart, this is implemented using `DiagnosticsProperty<void>` with
/// a description parameter, but we provide this dedicated class until
/// `DiagnosticsProperty` is migrated in Subtask 8.
///
/// **Dart Source:** `diagnostics.dart:1488-1510` (via DiagnosticsProperty)
public final class DiagnosticsMessageNode: DiagnosticsNode {
    /// Creates a diagnostics message node.
    ///
    /// **Dart Source:** `diagnostics.dart:1495-1509`
    public init(
        message: String,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info,
        allowWrap: Bool = true
    ) {
        self._message = message
        self._level = level
        self._allowWrap = allowWrap
        super.init(
            name: "",
            style: style,
            showName: false,
            showSeparator: false
        )
    }

    private let _message: String
    private let _level: DiagnosticLevel
    private let _allowWrap: Bool

    /// Returns the message as the description.
    public override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _message
    }

    /// Returns the configured level.
    public override var level: DiagnosticLevel { _level }

    /// Returns whether wrapping is allowed.
    public override var allowWrap: Bool { _allowWrap }
}

// MARK: - DiagnosticsSerializationDelegate Protocol

/// A delegate that configures how a [DiagnosticsNode] is serialized to JSON.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3564-3659
public protocol DiagnosticsSerializationDelegate {
    /// Controls how many levels of children will be included in the serialized
    /// hierarchy of children.
    ///
    /// Defaults to 0.
    ///
    /// **Dart Source:** `diagnostics.dart:3571-3576`
    var subtreeDepth: Int { get }

    /// Whether to include the properties of the [DiagnosticsNode] in the JSON
    /// serialization.
    ///
    /// **Dart Source:** `diagnostics.dart:3578-3582`
    var includeProperties: Bool { get }

    /// Provides additional key-value pairs to include for a given node.
    ///
    /// **Dart Source:** `diagnostics.dart:3597-3599`
    func additionalNodeProperties(_ node: any DiagnosticsNodeProtocol) -> [String: Any?]

    /// Filters the list of properties before serialization.
    ///
    /// **Dart Source:** `diagnostics.dart:3610-3614`
    func filterProperties(
        _ properties: [any DiagnosticsNodeProtocol],
        _ owner: any DiagnosticsNodeProtocol
    ) -> [any DiagnosticsNodeProtocol]

    /// Filters the list of children before serialization.
    ///
    /// **Dart Source:** `diagnostics.dart:3619-3623`
    func filterChildren(
        _ children: [any DiagnosticsNodeProtocol],
        _ owner: any DiagnosticsNodeProtocol
    ) -> [any DiagnosticsNodeProtocol]

    /// Truncates the list of nodes to the specified length.
    ///
    /// **Dart Source:** `diagnostics.dart:3631-3634`
    func truncateNodesList(
        _ nodes: [any DiagnosticsNodeProtocol],
        _ owner: (any DiagnosticsNodeProtocol)?
    ) -> [any DiagnosticsNodeProtocol]

    /// Returns a delegate to use for the children of the given node.
    ///
    /// **Dart Source:** `diagnostics.dart:3644-3656`
    func delegateForNode(_ node: any DiagnosticsNodeProtocol) -> DiagnosticsSerializationDelegate
}

/// Default implementation of `DiagnosticsSerializationDelegate`.
///
/// **Dart Source:** `diagnostics.dart:3661-3708`
public class DefaultDiagnosticsSerializationDelegate: DiagnosticsSerializationDelegate {
    /// Creates a default serialization delegate.
    ///
    /// **Dart Source:** `diagnostics.dart:3663-3668`
    public init(
        subtreeDepth: Int = 0,
        includeProperties: Bool = false
    ) {
        self._subtreeDepth = subtreeDepth
        self._includeProperties = includeProperties
    }

    private let _subtreeDepth: Int
    private let _includeProperties: Bool

    /// The depth of the subtree to serialize.
    ///
    /// **Dart Source:** `diagnostics.dart:3670-3672`
    public var subtreeDepth: Int { _subtreeDepth }

    /// Whether to include properties in the serialization.
    ///
    /// **Dart Source:** `diagnostics.dart:3674-3676`
    public var includeProperties: Bool { _includeProperties }

    /// Returns an empty dictionary (no additional properties).
    ///
    /// **Dart Source:** `diagnostics.dart:3678-3681`
    public func additionalNodeProperties(_ node: any DiagnosticsNodeProtocol) -> [String: Any?] {
        return [:]
    }

    /// Returns the properties unchanged.
    ///
    /// **Dart Source:** `diagnostics.dart:3683-3689`
    public func filterProperties(
        _ properties: [any DiagnosticsNodeProtocol],
        _ owner: any DiagnosticsNodeProtocol
    ) -> [any DiagnosticsNodeProtocol] {
        return properties
    }

    /// Returns the children unchanged.
    ///
    /// **Dart Source:** `diagnostics.dart:3691-3697`
    public func filterChildren(
        _ children: [any DiagnosticsNodeProtocol],
        _ owner: any DiagnosticsNodeProtocol
    ) -> [any DiagnosticsNodeProtocol] {
        return children
    }

    /// Returns the nodes unchanged (no truncation).
    ///
    /// **Dart Source:** `diagnostics.dart:3699-3702`
    public func truncateNodesList(
        _ nodes: [any DiagnosticsNodeProtocol],
        _ owner: (any DiagnosticsNodeProtocol)?
    ) -> [any DiagnosticsNodeProtocol] {
        return nodes
    }

    /// Returns a delegate with decremented subtree depth.
    ///
    /// **Dart Source:** `diagnostics.dart:3704-3708`
    public func delegateForNode(_ node: any DiagnosticsNodeProtocol) -> DiagnosticsSerializationDelegate {
        return DefaultDiagnosticsSerializationDelegate(
            subtreeDepth: subtreeDepth > 0 ? subtreeDepth - 1 : 0,
            includeProperties: includeProperties
        )
    }
}

// MARK: - ComputePropertyValueCallback

/// Signature for a callback that computes a property value on demand.
///
/// Used by `DiagnosticsProperty.lazy` to defer expensive value computations.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2556
public typealias ComputePropertyValueCallback<T> = () throws -> T?

// MARK: - DiagnosticsProperty

/// Property with a `value` of type `T`.
///
/// If the default `value.description` does not provide an adequate description
/// of the value, specify `description` defining a custom description.
///
/// The `showSeparator` property indicates whether a separator should be placed
/// between the property `name` and its `value`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2558-2901
open class DiagnosticsProperty<T>: DiagnosticsNode {
    /// Create a diagnostics property.
    ///
    /// The `level` argument is just a suggestion and can be overridden if
    /// something else about the property causes it to have a lower or higher
    /// level. For example, if the property value is null and `missingIfNull` is
    /// true, `level` is raised to `DiagnosticLevel.warning`.
    ///
    /// **Dart Source:** `diagnostics.dart:2566-2595`
    public init(
        _ name: String?,
        _ value: T?,
        description: String? = nil,
        ifNull: String? = nil,
        ifEmpty: String? = nil,
        showName: Bool = true,
        showSeparator: Bool = true,
        defaultValue: Any? = nil,
        tooltip: String? = nil,
        missingIfNull: Bool = false,
        linePrefix: String? = nil,
        expandableValue: Bool = false,
        allowWrap: Bool = true,
        allowNameWrap: Bool = true,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        self._description = description
        self._valueComputed = true
        self._value = value
        self._computeValue = nil
        self.ifNull = ifNull ?? (missingIfNull ? "MISSING" : nil)
        self.ifEmpty = ifEmpty
        self.defaultValue = defaultValue ?? kNoDefaultValue
        self.tooltip = tooltip
        self.missingIfNull = missingIfNull
        self.expandableValue = expandableValue
        self._allowWrap = allowWrap
        self._allowNameWrap = allowNameWrap
        self._defaultLevel = level
        super.init(
            name: name,
            style: style,
            showName: showName,
            showSeparator: showSeparator,
            linePrefix: linePrefix
        )
    }

    /// Property with a `value` that is computed only when needed.
    ///
    /// Use if computing the property `value` may throw an exception or is
    /// expensive.
    ///
    /// The `level` argument is just a suggestion and can be overridden
    /// if something else about the property causes it to have a lower or higher
    /// level. For example, if calling `computeValue` throws an exception, `level`
    /// will always return `DiagnosticLevel.error`.
    ///
    /// **Dart Source:** `diagnostics.dart:2597-2629`
    public init(
        lazy name: String?,
        computeValue: @escaping ComputePropertyValueCallback<T>,
        description: String? = nil,
        ifNull: String? = nil,
        ifEmpty: String? = nil,
        showName: Bool = true,
        showSeparator: Bool = true,
        defaultValue: Any? = nil,
        tooltip: String? = nil,
        missingIfNull: Bool = false,
        expandableValue: Bool = false,
        allowWrap: Bool = true,
        allowNameWrap: Bool = true,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        self._description = description
        self._valueComputed = false
        self._value = nil
        self._computeValue = computeValue
        self.ifNull = ifNull ?? (missingIfNull ? "MISSING" : nil)
        self.ifEmpty = ifEmpty
        self.defaultValue = defaultValue ?? kNoDefaultValue
        self.tooltip = tooltip
        self.missingIfNull = missingIfNull
        self.expandableValue = expandableValue
        self._allowWrap = allowWrap
        self._allowNameWrap = allowNameWrap
        self._defaultLevel = level
        super.init(
            name: name,
            style: style,
            showName: showName,
            showSeparator: showSeparator
        )
    }

    // MARK: - Stored Properties

    private let _description: String?

    /// Whether to expose properties and children of the value as properties and
    /// children.
    ///
    /// **Dart Source:** `diagnostics.dart:2633-2635`
    public let expandableValue: Bool

    private let _allowWrap: Bool
    private let _allowNameWrap: Bool

    /// **Dart Source:** `diagnostics.dart:2637-2638`
    open override var allowWrap: Bool { _allowWrap }

    /// **Dart Source:** `diagnostics.dart:2640-2641`
    open override var allowNameWrap: Bool { _allowNameWrap }

    // MARK: - Value Computation

    private var _value: T?
    private var _valueComputed: Bool
    private var _exception: Error?
    private let _computeValue: ComputePropertyValueCallback<T>?

    /// Returns the value of the property either from cache or by invoking a
    /// `ComputePropertyValueCallback`.
    ///
    /// If an exception is thrown invoking the `ComputePropertyValueCallback`,
    /// `value` returns nil and the exception thrown can be found via the
    /// `exception` property.
    ///
    /// See also:
    ///
    ///  * `valueToString`, which converts the property value to a string.
    ///
    /// **Dart Source:** `diagnostics.dart:2775-2789`
    open override var value: Any? {
        maybeCacheValue()
        return _value
    }

    /// Returns the typed value of the property.
    ///
    /// This is a Swift-specific convenience accessor for getting the value
    /// with its actual type rather than as `Any?`.
    public var typedValue: T? {
        maybeCacheValue()
        return _value
    }

    /// Exception thrown if accessing the property `value` threw an exception.
    ///
    /// Returns nil if computing the property value did not throw an exception.
    ///
    /// **Dart Source:** `diagnostics.dart:2797-2803`
    public var exception: Error? {
        maybeCacheValue()
        return _exception
    }

    /// Computes and caches the value if it hasn't been computed yet.
    ///
    /// **Dart Source:** `diagnostics.dart:2805-2820`
    private func maybeCacheValue() {
        if _valueComputed {
            return
        }

        _valueComputed = true
        assert(_computeValue != nil)
        do {
            _value = try _computeValue!()
        } catch {
            // The error is reported to inspector; rethrowing would destroy the
            // debugging experience.
            _exception = error
            _value = nil
        }
    }

    // MARK: - Default Value

    /// The default value of this property, when it has not been set to a specific
    /// value.
    ///
    /// For most `DiagnosticsProperty` classes, if the `value` of the property
    /// equals `defaultValue`, then the priority `level` of the property is
    /// downgraded to `DiagnosticLevel.fine` on the basis that the property value
    /// is uninteresting. This is implemented by `isInteresting`.
    ///
    /// The `defaultValue` is `kNoDefaultValue` by default. Otherwise it must be of
    /// type `T?`.
    ///
    /// **Dart Source:** `diagnostics.dart:2822-2832`
    public let defaultValue: Any

    /// Whether to consider the property's value interesting. When a property is
    /// uninteresting, its `level` is downgraded to `DiagnosticLevel.fine`
    /// regardless of the value provided as the constructor's `level` argument.
    ///
    /// **Dart Source:** `diagnostics.dart:2834-2837`
    public var isInteresting: Bool {
        if isNoDefaultValue(defaultValue) {
            return true
        }
        // Compare typed value with default value
        if let defaultTyped = defaultValue as? T, let currentValue = _value {
            return !areEqual(currentValue, defaultTyped)
        }
        // If defaultValue is nil and value is nil, they're equal (not interesting)
        if defaultValue is NoDefaultValue {
            return true
        }
        if _value == nil && (defaultValue as AnyObject?) == nil {
            return false
        }
        return true
    }

    /// Helper to compare two values of type T for equality.
    private func areEqual(_ lhs: T, _ rhs: T) -> Bool {
        // Use Equatable if available
        if let lhsEquatable = lhs as? any Equatable {
            return isEqualTo(lhsEquatable, rhs)
        }
        // Fall back to identity comparison for reference types
        // Use explicit type check to avoid "always succeeds" warning
        let lhsType = type(of: lhs as Any)
        if lhsType is AnyClass {
            // This is a reference type
            // swiftlint:disable:next force_cast
            let lhsObj = lhs as AnyObject
            let rhsObj = rhs as AnyObject
            return lhsObj === rhsObj
        }
        // For value types without Equatable, assume not equal
        return false
    }

    /// Helper for Equatable comparison
    private func isEqualTo<E: Equatable>(_ lhs: E, _ rhs: Any) -> Bool {
        guard let rhsTyped = rhs as? E else { return false }
        return lhs == rhsTyped
    }

    private let _defaultLevel: DiagnosticLevel

    // MARK: - Level

    /// Priority level of the diagnostic used to control which diagnostics should
    /// be shown and filtered.
    ///
    /// The property level defaults to the value specified by the `level`
    /// constructor argument. The level is raised to `DiagnosticLevel.error` if
    /// an `exception` was thrown getting the property `value`. The level is
    /// raised to `DiagnosticLevel.warning` if the property `value` is nil and
    /// the property is not allowed to be nil due to `missingIfNull`. The
    /// priority level is lowered to `DiagnosticLevel.fine` if the property
    /// `value` equals `defaultValue`.
    ///
    /// **Dart Source:** `diagnostics.dart:2841-2870`
    open override var level: DiagnosticLevel {
        #if !DEBUG
        return .hidden
        #else
        if _defaultLevel == .hidden {
            return _defaultLevel
        }

        if exception != nil {
            return .error
        }

        if _value == nil && missingIfNull {
            return .warning
        }

        if !isInteresting {
            return .fine
        }

        return _defaultLevel
        #endif
    }

    // MARK: - Description Properties

    /// Description if the property `value` is nil.
    ///
    /// **Dart Source:** `diagnostics.dart:2744-2745`
    public let ifNull: String?

    /// Description if the property description would otherwise be empty.
    ///
    /// **Dart Source:** `diagnostics.dart:2747-2748`
    public let ifEmpty: String?

    /// Optional tooltip typically describing the property.
    ///
    /// Example tooltip: 'physical pixels per logical pixel'
    ///
    /// If present, the tooltip is added in parenthesis after the raw value when
    /// generating the string description.
    ///
    /// **Dart Source:** `diagnostics.dart:2750-2756`
    public let tooltip: String?

    /// Whether a `value` of nil causes the property to have `level`
    /// `DiagnosticLevel.warning` warning that the property is missing a `value`.
    ///
    /// **Dart Source:** `diagnostics.dart:2758-2760`
    public let missingIfNull: Bool

    /// The type of the property `value`.
    ///
    /// This is determined from the type argument `T` used to instantiate the
    /// `DiagnosticsProperty` class. This means that the type is available even if
    /// `value` is nil, but it also means that the `propertyType` is only as
    /// accurate as the type provided when invoking the constructor.
    ///
    /// Generally, this is only useful for diagnostic tools that should display
    /// nil values in a manner consistent with the property type. For example, a
    /// tool might display a nil `Color` value as an empty rectangle instead of
    /// the word "nil".
    ///
    /// **Dart Source:** `diagnostics.dart:2762-2773`
    public var propertyType: Any.Type { T.self }

    // MARK: - String Conversion

    /// Returns a string representation of the property value.
    ///
    /// Subclasses should override this method instead of `toDescription` to
    /// customize how property values are converted to strings.
    ///
    /// Overriding this method ensures that behavior controlling how property
    /// values are decorated to generate a nice `toDescription` are consistent
    /// across all implementations. Debugging tools may also choose to use
    /// `valueToString` directly instead of `toDescription`.
    ///
    /// `parentConfiguration` specifies how the parent is rendered as text art.
    /// For example, if the parent places all properties on one line, the value
    /// of the property should be displayed without line breaks if possible.
    ///
    /// **Dart Source:** `diagnostics.dart:2695-2714`
    open func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        let v = typedValue
        // DiagnosticableTree values are shown using the shorter toStringShort()
        // instead of the longer toString() because the toString() for a
        // DiagnosticableTree value is likely too large to be useful.
        // Note: DiagnosticableTree will be added in a later subtask.
        // For now, we just use String(describing:).
        if let value = v {
            return String(describing: value)
        }
        return "nil"
    }

    /// Returns a description with a short summary of the node itself not
    /// including children or properties.
    ///
    /// **Dart Source:** `diagnostics.dart:2716-2735`
    open override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        if let description = _description {
            return addTooltip(description)
        }

        if exception != nil {
            return "EXCEPTION (\(type(of: exception!)))"
        }

        if ifNull != nil && _value == nil {
            return addTooltip(ifNull!)
        }

        var result = valueToString(parentConfiguration: parentConfiguration)
        if result.isEmpty, let ifEmpty = ifEmpty {
            result = ifEmpty
        }
        return addTooltip(result)
    }

    /// If a `tooltip` is specified, add the tooltip it to the end of `text`
    /// enclosing it parenthesis to disambiguate the tooltip from the rest of
    /// the text.
    ///
    /// **Dart Source:** `diagnostics.dart:2737-2742`
    private func addTooltip(_ text: String) -> String {
        guard let tooltip = tooltip else { return text }
        return "\(text) (\(tooltip))"
    }

    // MARK: - Children and Properties

    /// Properties of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:2874-2886`
    open override func getProperties() -> [any DiagnosticsNodeProtocol] {
        if expandableValue {
            // Note: Full implementation requires Diagnosticable protocol
            // which will be added in a later subtask.
            if let node = _value as? DiagnosticsNode {
                return node.getProperties()
            }
        }
        return []
    }

    /// Children of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:2888-2900`
    open override func getChildren() -> [any DiagnosticsNodeProtocol] {
        if expandableValue {
            // Note: Full implementation requires Diagnosticable protocol
            // which will be added in a later subtask.
            if let node = _value as? DiagnosticsNode {
                return node.getChildren()
            }
        }
        return []
    }

    // MARK: - JSON Serialization

    /// Serialize the node to a JSON map.
    ///
    /// **Dart Source:** `diagnostics.dart:2643-2693`
    open override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        #if !DEBUG
        return [:]
        #else
        var json = super.toJsonMap(delegate: delegate)

        if !isNoDefaultValue(defaultValue) {
            json["defaultValue"] = String(describing: defaultValue)
        }
        if let ifEmpty = ifEmpty {
            json["ifEmpty"] = ifEmpty
        }
        if let ifNull = ifNull {
            json["ifNull"] = ifNull
        }
        if let tooltip = tooltip {
            json["tooltip"] = tooltip
        }
        json["missingIfNull"] = missingIfNull
        if let exception = exception {
            json["exception"] = String(describing: exception)
        }
        json["propertyType"] = String(describing: propertyType)
        json["defaultLevel"] = String(describing: _defaultLevel)

        // Check if value is a DiagnosticsNode
        if _value is DiagnosticsNode {
            json["isDiagnosticableValue"] = true
        }

        // Handle numeric values
        if let numValue = _value as? Double {
            json["value"] = numValue.isFinite ? numValue : String(describing: numValue)
        } else if let numValue = _value as? Int {
            json["value"] = numValue
        } else if let stringValue = _value as? String {
            json["value"] = stringValue
        } else if let boolValue = _value as? Bool {
            json["value"] = boolValue
        } else if _value == nil {
            json["value"] = nil
        }

        return json
        #endif
    }
}

// MARK: - MessageProperty

/// Property which displays its string `description` as its value.
///
/// `MessageProperty` is typically used to provide a non-standard name-value pair
/// separator, as in the following example:
///
/// Example:
///
///     MessageProperty('size', 'Size is larger than screen size')
///
/// Renders as:
///
///     size: Size is larger than screen size
///
/// See also:
///
///  * `DiagnosticsNode.message`, which serves the same role for messages
///    without a clear property name.
///  * `StringProperty`, which is a better fit for properties with string values.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1902-1935
public final class MessageProperty: DiagnosticsProperty<Never> {
    /// Create a diagnostics property that displays a message.
    ///
    /// Messages have no concrete `value` (so `value` will return nil). The
    /// message is stored as the description.
    ///
    /// **Dart Source:** `diagnostics.dart:1924-1934`
    public init(
        _ name: String,
        _ message: String,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            nil,
            description: message,
            style: style,
            level: level
        )
    }
}

// MARK: - StringProperty

/// Property which encloses its string `value` in quotes.
///
/// See also:
///
///  * `MessageProperty`, which is a better fit for showing a message
///    instead of describing a property with a string value.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1937-1988
public final class StringProperty: DiagnosticsProperty<String> {
    /// Create a diagnostics property for strings.
    ///
    /// **Dart Source:** `diagnostics.dart:1943-1956`
    public init(
        _ name: String?,
        _ value: String?,
        description: String? = nil,
        tooltip: String? = nil,
        showName: Bool = true,
        defaultValue: Any? = nil,
        quoted: Bool = true,
        ifEmpty: String? = nil,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        self.quoted = quoted
        super.init(
            name,
            value,
            description: description,
            ifEmpty: ifEmpty,
            showName: showName,
            defaultValue: defaultValue,
            tooltip: tooltip,
            style: style,
            level: level
        )
    }

    /// Whether the value is enclosed in double quotes.
    ///
    /// **Dart Source:** `diagnostics.dart:1958-1959`
    public let quoted: Bool

    /// **Dart Source:** `diagnostics.dart:1961-1966`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        json["quoted"] = quoted
        return json
    }

    /// **Dart Source:** `diagnostics.dart:1968-1987`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        var text = _description ?? typedValue
        if let config = parentConfiguration, !config.lineBreakProperties, text != nil {
            // Escape linebreaks in multiline strings to avoid confusing output when
            // the parent of this node is trying to display all properties on the same
            // line.
            text = text!.replacingAll("\n", with: "\\n")
        }

        if quoted, let t = text {
            // An empty value would not appear empty after being surrounded with
            // quotes so we have to handle this case separately.
            if let ifEmpty = ifEmpty, t.isEmpty {
                return ifEmpty
            }
            return "\"\(t)\""
        }
        return text ?? "nil"
    }

    /// Access to the stored description for use in valueToString
    private var _description: String? { nil }
}

// MARK: - NumProperty

/// Abstract base class for properties representing numeric values.
///
/// This is a base class for `DoubleProperty` and `IntProperty`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 1990-2044
open class NumProperty<T: Numeric & Comparable>: DiagnosticsProperty<T> {
    /// Create a property for a numeric value.
    ///
    /// **Dart Source:** `diagnostics.dart:1990-2001`
    public init(
        _ name: String?,
        _ value: T?,
        ifNull: String? = nil,
        unit: String? = nil,
        showName: Bool = true,
        defaultValue: Any? = nil,
        tooltip: String? = nil,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        self.unit = unit
        super.init(
            name,
            value,
            ifNull: ifNull,
            showName: showName,
            defaultValue: defaultValue,
            tooltip: tooltip,
            style: style,
            level: level
        )
    }

    /// Property with a `value` that is computed only when needed.
    ///
    /// Use if computing the property `value` may throw an exception or is
    /// expensive.
    ///
    /// **Dart Source:** `diagnostics.dart:2003-2013`
    public init(
        lazy name: String?,
        computeValue: @escaping ComputePropertyValueCallback<T>,
        ifNull: String? = nil,
        unit: String? = nil,
        showName: Bool = true,
        defaultValue: Any? = nil,
        tooltip: String? = nil,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        self.unit = unit
        super.init(
            lazy: name,
            computeValue: computeValue,
            ifNull: ifNull,
            showName: showName,
            defaultValue: defaultValue,
            tooltip: tooltip,
            style: style,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2015-2024`
    open override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        if let unit = unit {
            json["unit"] = unit
        }
        json["numberToString"] = numberToString()
        return json
    }

    /// Optional unit the `value` is measured in.
    ///
    /// Unit must be acceptable to display immediately after a number with no
    /// spaces. For example: 'physical pixels per logical pixel' should be a
    /// `tooltip` not a `unit`.
    ///
    /// **Dart Source:** `diagnostics.dart:2026-2031`
    public let unit: String?

    /// String describing just the numeric `value` without a unit suffix.
    ///
    /// **Dart Source:** `diagnostics.dart:2033-2034`
    open func numberToString() -> String {
        fatalError("Subclasses must override numberToString()")
    }

    /// **Dart Source:** `diagnostics.dart:2036-2043`
    open override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        guard typedValue != nil else {
            return "nil"
        }

        if let unit = unit {
            return "\(numberToString())\(unit)"
        }
        return numberToString()
    }
}

// MARK: - DoubleProperty

/// Property describing a `Double` `value` with an optional `unit` of measurement.
///
/// Numeric formatting is optimized for debug message readability.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2046-2080
public class DoubleProperty: NumProperty<Double> {
    /// If specified, `unit` describes the unit for the `value` (e.g. px).
    ///
    /// **Dart Source:** `diagnostics.dart:2049-2061`
    public init(
        _ name: String?,
        _ value: Double?,
        ifNull: String? = nil,
        unit: String? = nil,
        tooltip: String? = nil,
        defaultValue: Any? = nil,
        showName: Bool = true,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            ifNull: ifNull,
            unit: unit,
            showName: showName,
            defaultValue: defaultValue,
            tooltip: tooltip,
            style: style,
            level: level
        )
    }

    /// Property with a `value` that is computed only when needed.
    ///
    /// Use if computing the property `value` may throw an exception or is
    /// expensive.
    ///
    /// **Dart Source:** `diagnostics.dart:2063-2076`
    public init(
        lazy name: String?,
        computeValue: @escaping ComputePropertyValueCallback<Double>,
        ifNull: String? = nil,
        showName: Bool = true,
        unit: String? = nil,
        tooltip: String? = nil,
        defaultValue: Any? = nil,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            lazy: name,
            computeValue: computeValue,
            ifNull: ifNull,
            unit: unit,
            showName: showName,
            defaultValue: defaultValue,
            tooltip: tooltip,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2078-2079`
    open override func numberToString() -> String {
        return debugFormatDouble(typedValue)
    }
}

// MARK: - IntProperty

/// An int valued property with an optional unit the value is measured in.
///
/// Examples of units include 'px' and 'ms'.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2082-2100
public final class IntProperty: NumProperty<Int> {
    /// Create a diagnostics property for integers.
    ///
    /// **Dart Source:** `diagnostics.dart:2085-2096`
    public init(
        _ name: String?,
        _ value: Int?,
        ifNull: String? = nil,
        showName: Bool = true,
        unit: String? = nil,
        defaultValue: Any? = nil,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            ifNull: ifNull,
            unit: unit,
            showName: showName,
            defaultValue: defaultValue,
            style: style,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2098-2099`
    public override func numberToString() -> String {
        guard let value = typedValue else {
            return "nil"
        }
        return String(value)
    }
}

// MARK: - PercentProperty

/// Property which clamps a `Double` to between 0 and 1 and formats it as a
/// percentage.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2102-2137
public final class PercentProperty: DoubleProperty {
    /// Create a diagnostics property for doubles that represent percentages or
    /// fractions.
    ///
    /// Setting `showName` to false is often reasonable for `PercentProperty`
    /// objects, as the fact that the property is shown as a percentage tends to
    /// be sufficient to disambiguate its meaning.
    ///
    /// **Dart Source:** `diagnostics.dart:2104-2119`
    public override init(
        _ name: String?,
        _ fraction: Double?,
        ifNull: String? = nil,
        unit: String? = nil,
        tooltip: String? = nil,
        defaultValue: Any? = nil,
        showName: Bool = true,
        style: DiagnosticsTreeStyle = .singleLine,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            fraction,
            ifNull: ifNull,
            unit: unit,
            tooltip: tooltip,
            defaultValue: defaultValue,
            showName: showName,
            style: style,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2121-2127`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        guard typedValue != nil else {
            return "nil"
        }

        if let unit = unit {
            return "\(numberToString()) \(unit)"
        }
        return numberToString()
    }

    /// **Dart Source:** `diagnostics.dart:2129-2136`
    public override func numberToString() -> String {
        guard let v = typedValue else {
            return "nil"
        }
        let clamped = max(0.0, min(1.0, v))
        return String(format: "%.1f%%", clamped * 100.0)
    }
}

// MARK: - FlagProperty

/// Property where the description is derived from a `Bool` value.
///
/// If the `value` is true and `ifTrue` is non-null, the description will use
/// `ifTrue`. If the `value` is false and `ifFalse` is non-null, the description
/// will use `ifFalse`.
///
/// `showName` defaults to false as typically `ifTrue` and `ifFalse` should be
/// descriptions that make the property name redundant.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2178-2248
public class FlagProperty: DiagnosticsProperty<Bool> {
    /// Constructs a FlagProperty with the given descriptions.
    ///
    /// **Dart Source:** `diagnostics.dart:2183-2192`
    public init(
        _ name: String,
        value: Bool?,
        ifTrue: String? = nil,
        ifFalse: String? = nil,
        showName: Bool = false,
        defaultValue: Any? = nil,
        level: DiagnosticLevel = .info
    ) {
        precondition(ifTrue != nil || ifFalse != nil,
            "At least one of ifTrue or ifFalse must be non-nil")
        self.ifTrue = ifTrue
        self.ifFalse = ifFalse
        super.init(
            name,
            value,
            showName: showName,
            defaultValue: defaultValue ?? kNoDefaultValue,
            level: level
        )
    }

    /// Description to use if the property `value` is true.
    ///
    /// If not specified and `value` equals true the property's priority `level`
    /// will be `DiagnosticLevel.hidden`.
    ///
    /// **Dart Source:** `diagnostics.dart:2207-2211`
    public let ifTrue: String?

    /// Description to use if the property value is false.
    ///
    /// If not specified and `value` equals false, the property's priority `level`
    /// will be `DiagnosticLevel.hidden`.
    ///
    /// **Dart Source:** `diagnostics.dart:2213-2217`
    public let ifFalse: String?

    /// **Dart Source:** `diagnostics.dart:2195-2205`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        if let ifTrueValue = ifTrue {
            json["ifTrue"] = ifTrueValue
        }
        if let ifFalseValue = ifFalse {
            json["ifFalse"] = ifFalseValue
        }
        return json
    }

    /// **Dart Source:** `diagnostics.dart:2219-2226`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        switch typedValue {
        case true where ifTrue != nil:
            return ifTrue!
        case false where ifFalse != nil:
            return ifFalse!
        default:
            return super.valueToString(parentConfiguration: parentConfiguration)
        }
    }

    /// **Dart Source:** `diagnostics.dart:2228-2240`
    public override var showName: Bool {
        if typedValue == nil ||
            ((typedValue ?? false) && ifTrue == nil) ||
            (!(typedValue ?? true) && ifFalse == nil) {
            // We are missing a description for the flag value so we need to show the
            // flag name. The property will have DiagnosticLevel.hidden for this case
            // so users will not see this property in this case unless they are
            // displaying hidden properties.
            return true
        }
        return super.showName
    }

    /// **Dart Source:** `diagnostics.dart:2242-2247`
    public override var level: DiagnosticLevel {
        switch typedValue {
        case true where ifTrue == nil:
            return .hidden
        case false where ifFalse == nil:
            return .hidden
        default:
            return super.level
        }
    }
}

// MARK: - ObjectFlagProperty

/// A property where the important diagnostic information is primarily whether
/// the `value` is present (non-null) or absent (null), rather than the actual
/// value of the property itself.
///
/// The `ifPresent` and `ifNull` strings describe the property `value` when it
/// is non-null and null respectively. If one of `ifPresent` or `ifNull` is
/// omitted, that is taken to mean that `level` should be
/// `DiagnosticLevel.hidden` when `value` is non-null or null respectively.
///
/// This kind of diagnostics property is typically used for opaque
/// values, like closures, where presenting the actual object is of dubious
/// value but where reporting the presence or absence of the value is much more
/// useful.
///
/// See also:
///
///  * `FlagsSummary`, which provides similar functionality but accepts multiple
///    flags under the same name, and is preferred if there are multiple such
///    values that can fit into a same category (such as "listeners").
///  * `FlagProperty`, which provides similar functionality describing whether
///    a `value` is true or false.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2356-2457
public class ObjectFlagProperty<T>: DiagnosticsProperty<T> {
    /// Create a diagnostics property for values that can be present (non-null) or
    /// absent (null), but for which the exact value's `Object.toString`
    /// representation is not very transparent (e.g. a callback).
    ///
    /// At least one of `ifPresent` or `ifNull` must be non-nil.
    ///
    /// **Dart Source:** `diagnostics.dart:2384-2391`
    public init(
        _ name: String,
        _ value: T?,
        ifPresent: String? = nil,
        ifNull: String? = nil,
        showName: Bool = false,
        level: DiagnosticLevel = .info
    ) {
        precondition(ifPresent != nil || ifNull != nil,
            "At least one of ifPresent or ifNull must be non-nil")
        self.ifPresent = ifPresent
        super.init(
            name,
            value,
            ifNull: ifNull,
            showName: showName,
            level: level
        )
    }

    /// Shorthand constructor to describe whether the property has a value.
    ///
    /// Only use if prefixing the property name with the word 'has' is a good
    /// flag name.
    ///
    /// **Dart Source:** `diagnostics.dart:2393-2399`
    public convenience init(
        has name: String,
        _ value: T?,
        level: DiagnosticLevel = .info
    ) {
        self.init(
            name,
            value,
            ifPresent: "has \(name)",
            showName: false,
            level: level
        )
    }

    /// Description to use if the property `value` is not null.
    ///
    /// If the property `value` is not null and `ifPresent` is null, the
    /// `level` for the property is `DiagnosticLevel.hidden` and the description
    /// from superclass is used.
    ///
    /// **Dart Source:** `diagnostics.dart:2401-2406`
    public let ifPresent: String?

    /// **Dart Source:** `diagnostics.dart:2408-2420`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        if typedValue != nil {
            if let ifPresentValue = ifPresent {
                return ifPresentValue
            }
        } else {
            if let ifNullValue = ifNull {
                return ifNullValue
            }
        }
        return super.valueToString(parentConfiguration: parentConfiguration)
    }

    /// **Dart Source:** `diagnostics.dart:2422-2432`
    public override var showName: Bool {
        if (typedValue != nil && ifPresent == nil) || (typedValue == nil && ifNull == nil) {
            // We are missing a description for the flag value so we need to show the
            // flag name. The property will have DiagnosticLevel.hidden for this case
            // so users will not see this property in this case unless they are
            // displaying hidden properties.
            return true
        }
        return super.showName
    }

    /// **Dart Source:** `diagnostics.dart:2434-2447`
    public override var level: DiagnosticLevel {
        if typedValue != nil {
            if ifPresent == nil {
                return .hidden
            }
        } else {
            if ifNull == nil {
                return .hidden
            }
        }
        return super.level
    }

    /// **Dart Source:** `diagnostics.dart:2449-2456`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        if let ifPresentValue = ifPresent {
            json["ifPresent"] = ifPresentValue
        }
        return json
    }
}

// MARK: - FlagsSummary

/// A summary of multiple properties, indicating whether each of them is present
/// (non-null) or absent (null).
///
/// Each entry of `value` is described by its key. The eventual description will
/// be a list of keys of non-null entries.
///
/// The `ifEmpty` describes the entire collection of `value` when it contains no
/// non-null entries. If `ifEmpty` is omitted, `level` will be
/// `DiagnosticLevel.hidden` when `value` contains no non-null entries.
///
/// This kind of diagnostics property is typically used for opaque
/// values, like closures, where presenting the actual object is of dubious
/// value but where reporting the presence or absence of the value is much more
/// useful.
///
/// See also:
///
///  * `ObjectFlagProperty`, which provides similar functionality but accepts
///    only one flag, and is preferred if there is only one entry.
///  * `IterableProperty`, which provides similar functionality describing
///    the values a collection of objects.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2459-2549
public class FlagsSummary<T>: DiagnosticsProperty<[String: T?]> {
    /// Create a summary for multiple properties, indicating whether each of them
    /// is present (non-null) or absent (null).
    ///
    /// **Dart Source:** `diagnostics.dart:2486-2493`
    public init(
        _ name: String,
        _ value: [String: T?],
        ifEmpty: String? = nil,
        showName: Bool = true,
        showSeparator: Bool = true,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            ifEmpty: ifEmpty,
            showName: showName,
            showSeparator: showSeparator,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2495-2496`
    public override var value: Any? { typedValue }

    /// The typed value of this property as a dictionary.
    public var typedValueDict: [String: T?] {
        return typedValue ?? [:]
    }

    /// **Dart Source:** `diagnostics.dart:2498-2511`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        if !hasNonNullEntry() && ifEmpty != nil {
            return ifEmpty!
        }

        let formattedValues = self.formattedValues()
        if let parentConfig = parentConfiguration, !parentConfig.lineBreakProperties {
            // Always display the value as a single line and enclose the iterable
            // value in brackets to avoid ambiguity.
            return "[\(formattedValues.joined(separator: ", "))]"
        }

        return formattedValues.joined(separator: isSingleLine(style) ? ", " : "\n")
    }

    /// Priority level of the diagnostic used to control which diagnostics should
    /// be shown and filtered.
    ///
    /// If `ifEmpty` is null and the `value` contains no non-null entries, then
    /// level `DiagnosticLevel.hidden` is returned.
    ///
    /// **Dart Source:** `diagnostics.dart:2513-2525`
    public override var level: DiagnosticLevel {
        if !hasNonNullEntry() && ifEmpty == nil {
            return .hidden
        }
        return super.level
    }

    /// **Dart Source:** `diagnostics.dart:2527-2534`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        if let dict = typedValue, !dict.isEmpty {
            json["values"] = formattedValues()
        }
        return json
    }

    /// **Dart Source:** `diagnostics.dart:2536`
    private func hasNonNullEntry() -> Bool {
        guard let dict = typedValue else { return false }
        return dict.values.contains { $0 != nil }
    }

    /// An iterable of each entry's description in `value`.
    ///
    /// For a non-null value, its description is its key.
    /// For a null value, it is omitted.
    ///
    /// **Dart Source:** `diagnostics.dart:2544-2548`
    private func formattedValues() -> [String] {
        guard let dict = typedValue else { return [] }
        return dict.compactMap { key, value in
            value != nil ? key : nil
        }
    }
}

// MARK: - IterableProperty

/// Property with an `Iterable<T>` `value` that can be displayed with
/// different `DiagnosticsTreeStyle` for custom rendering.
///
/// If `style` is `DiagnosticsTreeStyle.singleLine`, the iterable is described
/// as a comma separated list, otherwise the iterable is described as a line
/// break separated list.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2250-2329
public class IterableProperty<T>: DiagnosticsProperty<[T]> {
    /// Create a diagnostics property for iterables (e.g. lists).
    ///
    /// The `ifEmpty` argument is used to indicate how an iterable `value` with 0
    /// elements is displayed. If `ifEmpty` equals nil that indicates that an
    /// empty iterable `value` is not interesting to display similar to how
    /// `defaultValue` is used to indicate that a specific concrete value is not
    /// interesting to display.
    ///
    /// **Dart Source:** `diagnostics.dart:2264-2274`
    public init(
        _ name: String,
        _ value: [T]?,
        defaultValue: Any? = nil,
        ifNull: String? = nil,
        ifEmpty: String? = "[]",
        style: DiagnosticsTreeStyle? = nil,
        showName: Bool = true,
        showSeparator: Bool = true,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            ifNull: ifNull,
            ifEmpty: ifEmpty,
            showName: showName,
            showSeparator: showSeparator,
            defaultValue: defaultValue ?? kNoDefaultValue,
            style: style ?? .singleLine,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2276-2301`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        guard let array = typedValue else {
            return "nil"
        }

        if array.isEmpty {
            return ifEmpty ?? "[]"
        }

        let formattedValues: [String] = array.map { v in
            if T.self == Double.self, let doubleValue = v as? Double {
                return debugFormatDouble(doubleValue)
            } else {
                return String(describing: v)
            }
        }

        if let parentConfig = parentConfiguration, !parentConfig.lineBreakProperties {
            // Always display the value as a single line and enclose the iterable
            // value in brackets to avoid ambiguity.
            return "[\(formattedValues.joined(separator: ", "))]"
        }

        return formattedValues.joined(separator: isSingleLine(style) ? ", " : "\n")
    }

    /// Priority level of the diagnostic used to control which diagnostics should
    /// be shown and filtered.
    ///
    /// If `ifEmpty` is nil and the `value` is an empty `Iterable` then level
    /// `DiagnosticLevel.fine` is returned in a similar way to how an
    /// `ObjectFlagProperty` handles when `ifNull` is nil and the `value` is
    /// nil.
    ///
    /// **Dart Source:** `diagnostics.dart:2303-2319`
    public override var level: DiagnosticLevel {
        if ifEmpty == nil,
           let array = typedValue,
           array.isEmpty,
           super.level != .hidden {
            return .fine
        }
        return super.level
    }

    /// **Dart Source:** `diagnostics.dart:2321-2328`
    public override func toJsonMap(delegate: DiagnosticsSerializationDelegate) -> [String: Any?] {
        var json = super.toJsonMap(delegate: delegate)
        if let array = typedValue {
            json["values"] = array.map { String(describing: $0) }
        }
        return json
    }
}

// MARK: - EnumProperty

/// `DiagnosticsProperty` that has an `Enum` as value.
///
/// The enum value is displayed with the enum name stripped. For example:
/// `HitTestBehavior.deferToChild` is shown as `deferToChild`.
///
/// This class can be used with enums and returns the enum's name. It
/// can also be used with nullable properties; the null value is represented as
/// `null`.
///
/// See also:
///
///  * `DiagnosticsProperty` which documents named parameters common to all
///    `DiagnosticsProperty`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2331-2354
public class EnumProperty<T: RawRepresentable>: DiagnosticsProperty<T> where T.RawValue: CustomStringConvertible {
    /// Create a diagnostics property that displays an enum.
    ///
    /// **Dart Source:** `diagnostics.dart:2345-2348`
    public init(
        _ name: String,
        _ value: T?,
        defaultValue: Any? = nil,
        level: DiagnosticLevel = .info
    ) {
        super.init(
            name,
            value,
            defaultValue: defaultValue ?? kNoDefaultValue,
            level: level
        )
    }

    /// **Dart Source:** `diagnostics.dart:2350-2353`
    public override func valueToString(parentConfiguration: TextTreeConfiguration? = nil) -> String {
        guard let enumValue = typedValue else {
            return "null"
        }
        // We use String(describing:) as it typically returns just the case name for enums
        let description = String(describing: enumValue)
        // If the description contains a dot (TypeName.caseName), extract just the case name
        if let dotIndex = description.lastIndex(of: ".") {
            return String(description[description.index(after: dotIndex)...])
        }
        return description
    }
}

// MARK: - EnumProperty for CaseIterable Enums

/// Convenience extension for enums that are also CaseIterable.
/// This version works with String-backed enums without requiring RawRepresentable.
extension DiagnosticsProperty where T: CaseIterable & CustomStringConvertible {
    /// Create a diagnostics property that displays an enum.
    ///
    /// This initializer works with enums that conform to CaseIterable and CustomStringConvertible.
    public static func enumProperty(
        _ name: String,
        _ value: T?,
        defaultValue: Any? = nil,
        level: DiagnosticLevel = .info
    ) -> DiagnosticsProperty<T> {
        return DiagnosticsProperty<T>(
            name,
            value,
            defaultValue: defaultValue ?? kNoDefaultValue,
            level: level
        )
    }
}

// MARK: - Helper Functions

/// Returns a 5 character long hexadecimal string generated from
/// [Object.hashCode]'s 20 least-significant bits.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2974-2976
public func shortHash(_ object: Any?) -> String {
    guard let obj = object else {
        return "00000"
    }
    // Use ObjectIdentifier for reference types, which provides a stable hash.
    // In Swift, all values can be bridged to AnyObject.
    let anyObj = obj as AnyObject
    let hashCode = ObjectIdentifier(anyObj).hashValue
    // Get unsigned 20 least significant bits and format as hex
    let unsigned20 = UInt(bitPattern: hashCode) & 0xFFFFF
    return String(format: "%05x", unsigned20)
}

/// Returns a summary of the runtime type and hash code of `object`.
///
/// See also:
///
///  * [Object.hashCode], a value used when placing an object in a [Map] or
///    other similar data structure, and which is also used in debug output to
///    distinguish instances of the same class (hash collisions are
///    possible, but rare enough that its use in debug output is helpful).
///  * [shortHash], which is used to generate the hash code portion of the
///    result.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2987-2988
public func describeIdentity(_ object: Any?) -> String {
    return "\(objectRuntimeType(object, "<optimized out>"))#\(shortHash(object))"
}

/// Returns a short description of an enum value.
///
/// Strips off the enum class name from the `enumEntry.toString()`.
///
/// For real enums, this is equivalent to calling the `name` getter on the enum
/// value.
///
/// This function can also be used with classes whose `toString` return a value
/// in a similar format to enums.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3021-3031
public func describeEnum(_ enumEntry: Any) -> String {
    let description = String(describing: enumEntry)
    if let dotIndex = description.lastIndex(of: ".") {
        return String(description[description.index(after: dotIndex)...])
    }
    return description
}

// MARK: - DiagnosticPropertiesBuilder

/// Builder for accumulating properties and configuration used to assemble a
/// `DiagnosticsNode` tree.
///
/// Wrap a [value] in a `DiagnosticPropertiesBuilder` to customize how it is
/// added to a `DiagnosticsNode` tree.
///
/// See also:
///
///  * `Diagnosticable.debugFillProperties`, the typical place
///    `DiagnosticPropertiesBuilder` is used.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3036-3087
public class DiagnosticPropertiesBuilder {
    /// Creates a `DiagnosticPropertiesBuilder`.
    ///
    /// **Dart Source:** `diagnostics.dart:3038`
    public init() {}

    /// Add a property to the list of properties.
    ///
    /// **Dart Source:** `diagnostics.dart:3050-3052`
    public func add(_ property: any DiagnosticsNodeProtocol) {
        #if DEBUG
        _properties.append(property)
        #endif
    }

    /// List of properties (to be filled in by subclasses).
    ///
    /// **Dart Source:** `diagnostics.dart:3055-3056`
    private var _properties: [any DiagnosticsNodeProtocol] = []

    /// Properties of this diagnostics node.
    ///
    /// **Dart Source:** `diagnostics.dart:3058-3059`
    public var properties: [any DiagnosticsNodeProtocol] { _properties }

    /// Default style to use for the node.
    ///
    /// Initializes to `DiagnosticsTreeStyle.sparse`.
    ///
    /// **Dart Source:** `diagnostics.dart:3061-3067`
    public var defaultDiagnosticsTreeStyle: DiagnosticsTreeStyle = .sparse

    /// Description to show if the node has no displayed properties or children.
    ///
    /// **Dart Source:** `diagnostics.dart:3069-3073`
    public var emptyBodyDescription: String?
}

// MARK: - Diagnosticable Protocol

/// A protocol providing debug diagnostics for objects.
///
/// Types conforming to `Diagnosticable` can provide rich debugging information
/// by implementing `debugFillProperties` to add properties to a
/// `DiagnosticPropertiesBuilder`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3089-3336
public protocol Diagnosticable: AnyObject {
    /// A brief description of this object, usually just the `runtimeType` and the
    /// `hashCode`.
    ///
    /// See also:
    ///
    ///  * `toString`, for a detailed description of the object.
    ///
    /// **Dart Source:** `diagnostics.dart:3089-3096`
    func toStringShort() -> String

    /// Returns a debug representation of the object that is used by debugging
    /// tools and by `DiagnosticsNode.toStringDeep`.
    ///
    /// Leave `name` as nil if there is not a meaningful description of the
    /// relationship between the this node and its parent.
    ///
    /// Typically the `style` argument is only specified to indicate an atypical
    /// relationship between the parent and the node. For example, pass
    /// `DiagnosticsTreeStyle.offstage` to indicate that a node is offstage.
    ///
    /// **Dart Source:** `diagnostics.dart:3119-3121`
    func toDiagnosticsNode(name: String?, style: DiagnosticsTreeStyle?) -> DiagnosticsNode

    /// Add additional properties associated with the node.
    ///
    /// Use the most specific `DiagnosticsProperty` existing subclass to describe
    /// each property instead of the `DiagnosticsProperty` base class.
    ///
    /// Used by `toDiagnosticsNode` and `toString`.
    ///
    /// Do not add values that have lifetime shorter than the object.
    ///
    /// **Dart Source:** `diagnostics.dart:3333-3335`
    func debugFillProperties(_ properties: DiagnosticPropertiesBuilder)
}

/// Default implementations for `Diagnosticable`.
public extension Diagnosticable {
    /// A brief description of this object, usually just the `runtimeType` and the
    /// `hashCode`.
    ///
    /// **Dart Source:** `diagnostics.dart:3096`
    func toStringShort() -> String {
        return describeIdentity(self)
    }

    /// Returns a string representation of this object at the given `minLevel`.
    ///
    /// In debug mode, returns a full representation using `toDiagnosticsNode`.
    /// In release mode, returns just `toStringShort()`.
    ///
    /// **Dart Source:** `diagnostics.dart:3098-3108`
    func toString(minLevel: DiagnosticLevel = .info) -> String {
        #if DEBUG
        return toDiagnosticsNode(name: nil, style: .singleLine)
            .toString(parentConfiguration: nil, minLevel: minLevel)
        #else
        return toStringShort()
        #endif
    }

    /// Returns a debug representation of the object that is used by debugging
    /// tools and by `DiagnosticsNode.toStringDeep`.
    ///
    /// **Dart Source:** `diagnostics.dart:3119-3121`
    func toDiagnosticsNode(name: String? = nil, style: DiagnosticsTreeStyle? = nil) -> DiagnosticsNode {
        return DiagnosticableNode<Self>(name: name, value: self, style: style)
    }

    /// Add additional properties associated with the node.
    ///
    /// Default implementation does nothing. Subclasses should override to add
    /// their own properties.
    ///
    /// **Dart Source:** `diagnostics.dart:3333-3335`
    func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // Default empty implementation
    }
}

// MARK: - DiagnosticableTree Protocol

/// A protocol providing string and `DiagnosticsNode` debug representations
/// describing the properties and children of an object.
///
/// The string debug representation is generated from the intermediate
/// `DiagnosticsNode` representation. The `DiagnosticsNode` representation is
/// also used by debugging tools displaying interactive trees of objects and
/// properties.
///
/// See also:
///
///  * `DiagnosticableTreeMixin`, a mixin that implements this protocol.
///  * `Diagnosticable`, which should be used instead of this protocol to
///    provide diagnostics for objects without children.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3338-3452
public protocol DiagnosticableTree: Diagnosticable {
    /// Returns a one-line detailed description of the object.
    ///
    /// This description is often somewhat long. This includes the same
    /// information given by `toStringDeep`, but does not recurse to any children.
    ///
    /// `joiner` specifies the string which is place between each part obtained
    /// from `debugFillProperties`. Passing a string such as `'\n '` will result
    /// in a multiline string that indents the properties of the object below its
    /// name (as per `toString`).
    ///
    /// `minLevel` specifies the minimum `DiagnosticLevel` for properties included
    /// in the output.
    ///
    /// **Dart Source:** `diagnostics.dart:3373-3388`
    func toStringShallow(joiner: String, minLevel: DiagnosticLevel) -> String

    /// Returns a string representation of this node and its descendants.
    ///
    /// `prefixLineOne` will be added to the front of the first line of the
    /// output. `prefixOtherLines` will be added to the front of each other line.
    /// If `prefixOtherLines` is nil, the `prefixLineOne` is used for every line.
    /// By default, there is no prefix.
    ///
    /// `minLevel` specifies the minimum `DiagnosticLevel` for properties included
    /// in the output.
    ///
    /// `wrapWidth` specifies the column number where word wrapping will be
    /// applied.
    ///
    /// **Dart Source:** `diagnostics.dart:3411-3423`
    func toStringDeep(
        prefixLineOne: String,
        prefixOtherLines: String?,
        minLevel: DiagnosticLevel,
        wrapWidth: Int
    ) -> String

    /// Returns a list of `DiagnosticsNode` objects describing this node's
    /// children.
    ///
    /// Children that are offstage should be added with `style` set to
    /// `DiagnosticsTreeStyle.offstage` to indicate that they are offstage.
    ///
    /// The list must not contain any null entries. If there are explicit null
    /// children to report, consider `DiagnosticsNode.message` or
    /// `DiagnosticsProperty<Object>` as possible `DiagnosticsNode` objects to
    /// provide.
    ///
    /// Used by `toStringDeep`, `toDiagnosticsNode` and `toStringShallow`.
    ///
    /// **Dart Source:** `diagnostics.dart:3450-3451`
    func debugDescribeChildren() -> [any DiagnosticsNodeProtocol]
}

/// Default implementations for `DiagnosticableTree`.
public extension DiagnosticableTree {
    /// Default implementation for `toStringShort`.
    ///
    /// **Dart Source:** `diagnostics.dart:3425-3426`
    func toStringShort() -> String {
        return describeIdentity(self)
    }

    /// Returns a one-line detailed description of the object.
    ///
    /// **Dart Source:** `diagnostics.dart:3373-3388`
    func toStringShallow(joiner: String = ", ", minLevel: DiagnosticLevel = .debug) -> String {
        #if DEBUG
        var result = ""
        result += toString(minLevel: minLevel)
        result += joiner
        let builder = DiagnosticPropertiesBuilder()
        debugFillProperties(builder)
        let filteredProperties = builder.properties.filter { !$0.isFiltered(minLevel) }
        result += filteredProperties.map { node in
            if let diagnosticsNode = node as? DiagnosticsNode {
                return diagnosticsNode.toString(parentConfiguration: nil, minLevel: minLevel)
            }
            return node.toDescription(parentConfiguration: nil)
        }.joined(separator: joiner)
        return result
        #else
        return toString(minLevel: minLevel)
        #endif
    }

    /// Returns a string representation of this node and its descendants.
    ///
    /// **Dart Source:** `diagnostics.dart:3411-3423`
    func toStringDeep(
        prefixLineOne: String = "",
        prefixOtherLines: String? = nil,
        minLevel: DiagnosticLevel = .debug,
        wrapWidth: Int = 65
    ) -> String {
        return toDiagnosticsNode(name: nil, style: nil).toStringDeep(
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            minLevel: minLevel,
            wrapWidth: wrapWidth
        )
    }

    /// Returns a debug representation of the object that is used by debugging
    /// tools and by `DiagnosticsNode.toStringDeep`.
    ///
    /// **Dart Source:** `diagnostics.dart:3428-3431`
    func toDiagnosticsNode(name: String? = nil, style: DiagnosticsTreeStyle? = nil) -> DiagnosticsNode {
        return DiagnosticableTreeNodeImpl(name: name, value: self, style: style)
    }

    /// Returns a list of `DiagnosticsNode` objects describing this node's
    /// children.
    ///
    /// **Dart Source:** `diagnostics.dart:3450-3451`
    func debugDescribeChildren() -> [any DiagnosticsNodeProtocol] {
        return []
    }
}

// MARK: - DiagnosticableTreeMixin

/// A mixin that helps dump string and `DiagnosticsNode` representations of trees.
///
/// This mixin is identical to class `DiagnosticableTree`.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3454-3509
public protocol DiagnosticableTreeMixin: DiagnosticableTree {}

/// Default implementations for `DiagnosticableTreeMixin`.
/// These implementations match `DiagnosticableTree` extension methods.
public extension DiagnosticableTreeMixin {
    /// Returns a string representation of this object.
    ///
    /// **Dart Source:** `diagnostics.dart:3458-3461`
    func toString(minLevel: DiagnosticLevel = .info) -> String {
        return toDiagnosticsNode(name: nil, style: .singleLine).toString(minLevel: minLevel)
    }

    /// Returns a one-line detailed description of the object.
    ///
    /// **Dart Source:** `diagnostics.dart:3463-3479`
    func toStringShallow(joiner: String = ", ", minLevel: DiagnosticLevel = .debug) -> String {
        #if DEBUG
        var result = ""
        result += toStringShort()
        result += joiner
        let builder = DiagnosticPropertiesBuilder()
        debugFillProperties(builder)
        let filteredProperties = builder.properties.filter { !$0.isFiltered(minLevel) }
        result += filteredProperties.map { node in
            if let diagnosticsNode = node as? DiagnosticsNode {
                return diagnosticsNode.toString(parentConfiguration: nil, minLevel: minLevel)
            }
            return node.toDescription(parentConfiguration: nil)
        }.joined(separator: joiner)
        return result
        #else
        return toString(minLevel: minLevel)
        #endif
    }

    /// Returns a string representation of this node and its descendants.
    ///
    /// **Dart Source:** `diagnostics.dart:3481-3494`
    func toStringDeep(
        prefixLineOne: String = "",
        prefixOtherLines: String? = nil,
        minLevel: DiagnosticLevel = .debug,
        wrapWidth: Int = 65
    ) -> String {
        return toDiagnosticsNode(name: nil, style: nil).toStringDeep(
            prefixLineOne: prefixLineOne,
            prefixOtherLines: prefixOtherLines,
            minLevel: minLevel,
            wrapWidth: wrapWidth
        )
    }

    /// **Dart Source:** `diagnostics.dart:3496-3497`
    func toStringShort() -> String {
        return describeIdentity(self)
    }

    /// **Dart Source:** `diagnostics.dart:3499-3502`
    func toDiagnosticsNode(name: String? = nil, style: DiagnosticsTreeStyle? = nil) -> DiagnosticsNode {
        return DiagnosticableTreeNodeImpl(name: name, value: self, style: style)
    }

    /// **Dart Source:** `diagnostics.dart:3504-3505`
    func debugDescribeChildren() -> [any DiagnosticsNodeProtocol] {
        return []
    }

    /// **Dart Source:** `diagnostics.dart:3507-3508`
    func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
        // Default empty implementation
    }
}

// MARK: - DiagnosticableNode

/// `DiagnosticsNode` for a `Diagnosticable` value.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2903-2962
public class DiagnosticableNode<T: Diagnosticable>: DiagnosticsNode {
    /// Creates a `DiagnosticsNode` for a `Diagnosticable` value.
    ///
    /// **Dart Source:** `diagnostics.dart:2905-2911`
    public init(
        name: String?,
        value: T,
        style: DiagnosticsTreeStyle?
    ) {
        self._value = value
        super.init(name: name, style: style)
    }

    private let _value: T

    /// The value associated with this node.
    ///
    /// **Dart Source:** `diagnostics.dart:2913-2916`
    public override var value: Any? { _value }

    /// The typed value associated with this node.
    public var typedValue: T { _value }

    private var _cachedBuilder: DiagnosticPropertiesBuilder?

    /// **Dart Source:** `diagnostics.dart:2918-2933`
    private var builder: DiagnosticPropertiesBuilder {
        #if DEBUG
        if _cachedBuilder == nil {
            _cachedBuilder = DiagnosticPropertiesBuilder()
            _value.debugFillProperties(_cachedBuilder!)
        }
        return _cachedBuilder!
        #else
        return DiagnosticPropertiesBuilder()
        #endif
    }

    /// Style to use for this node.
    ///
    /// **Dart Source:** `diagnostics.dart:2935-2941`
    public override var style: DiagnosticsTreeStyle? {
        return super.style ?? builder.defaultDiagnosticsTreeStyle
    }

    /// Description to show if the node has no displayed properties or children.
    ///
    /// **Dart Source:** `diagnostics.dart:2943-2944`
    public override var emptyBodyDescription: String? {
        return builder.emptyBodyDescription
    }

    /// Properties of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:2946-2947`
    public override func getProperties() -> [any DiagnosticsNodeProtocol] {
        return builder.properties
    }

    /// Returns a description with a short summary of the node itself.
    ///
    /// **Dart Source:** `diagnostics.dart:2949-2961`
    public override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _value.toStringShort()
    }
}

// MARK: - DiagnosticableTreeNode

/// `DiagnosticsNode` for a `DiagnosticableTree` value.
///
/// Note: In Swift, we can't use existential types (like `any DiagnosticableTree`) as generic
/// type parameters for `DiagnosticableNode<T>`. Therefore, we provide a separate
/// `DiagnosticableTreeNodeImpl` class that directly extends `DiagnosticsNode` and works
/// with existential types.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2964-3034

/// Typealias for compatibility - points to the implementation class.
public typealias DiagnosticableTreeNode = DiagnosticableTreeNodeImpl

/// Implementation of `DiagnosticsNode` for `DiagnosticableTree` values.
///
/// This class exists because Swift cannot use existential types like `any DiagnosticableTree`
/// as generic type parameters. It provides the same functionality as `DiagnosticableNode<T>`
/// but works with the `any DiagnosticableTree` existential type.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 2964-3034
public class DiagnosticableTreeNodeImpl: DiagnosticsNode {
    /// Creates a `DiagnosticsNode` for a `DiagnosticableTree` value.
    ///
    /// **Dart Source:** `diagnostics.dart:2969-2975`
    public init(
        name: String?,
        value: any DiagnosticableTree,
        style: DiagnosticsTreeStyle?
    ) {
        self._value = value
        super.init(name: name, style: style)
    }

    private let _value: any DiagnosticableTree
    private var _cachedBuilder: DiagnosticPropertiesBuilder?

    /// The value associated with this node.
    ///
    /// **Dart Source:** `diagnostics.dart:2913-2916`
    public override var value: Any? { _value }

    /// Builder for accumulating properties.
    private var builder: DiagnosticPropertiesBuilder {
        #if DEBUG
        if _cachedBuilder == nil {
            _cachedBuilder = DiagnosticPropertiesBuilder()
            _value.debugFillProperties(_cachedBuilder!)
        }
        return _cachedBuilder!
        #else
        return DiagnosticPropertiesBuilder()
        #endif
    }

    /// Style to use for this node.
    ///
    /// **Dart Source:** `diagnostics.dart:2935-2941`
    public override var style: DiagnosticsTreeStyle? {
        return super.style ?? builder.defaultDiagnosticsTreeStyle
    }

    /// Description to show if the node has no displayed properties or children.
    ///
    /// **Dart Source:** `diagnostics.dart:2943-2944`
    public override var emptyBodyDescription: String? {
        return builder.emptyBodyDescription
    }

    /// Properties of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:2946-2947`
    public override func getProperties() -> [any DiagnosticsNodeProtocol] {
        return builder.properties
    }

    /// Children of this `DiagnosticsNode`.
    ///
    /// **Dart Source:** `diagnostics.dart:2977-2981`
    public override func getChildren() -> [any DiagnosticsNodeProtocol] {
        return _value.debugDescribeChildren()
    }

    /// Returns a description with a short summary of the node itself.
    ///
    /// **Dart Source:** `diagnostics.dart:2949-2961`
    public override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _value.toStringShort()
    }
}

// MARK: - DiagnosticsBlock

/// `DiagnosticsNode` that exists mainly to provide a container for other
/// diagnostics that typically lacks a meaningful value of its own.
///
/// This class is typically used for displaying complex nested error messages.
///
/// **Dart Source:** `packages/flutter/lib/src/foundation/diagnostics.dart`
/// **Lines:** 3511-3557
public class DiagnosticsBlock: DiagnosticsNode {
    /// Creates a diagnostic with properties specified by `properties` and
    /// children specified by `children`.
    ///
    /// **Dart Source:** `diagnostics.dart:3518-3533`
    public init(
        name: String? = nil,
        style: DiagnosticsTreeStyle = .whitespace,
        showName: Bool = true,
        showSeparator: Bool = true,
        linePrefix: String? = nil,
        value: Any? = nil,
        description: String? = nil,
        level: DiagnosticLevel = .info,
        allowTruncate: Bool = false,
        children: [any DiagnosticsNodeProtocol] = [],
        properties: [any DiagnosticsNodeProtocol] = []
    ) {
        self._value = value
        self._description = description ?? ""
        self._level = level
        self._allowTruncate = allowTruncate
        self._children = children
        self._properties = properties
        super.init(
            name: name,
            style: style,
            showName: showName && name != nil,
            showSeparator: showSeparator,
            linePrefix: linePrefix
        )
    }

    private let _value: Any?
    private let _description: String
    private let _level: DiagnosticLevel
    private let _allowTruncate: Bool
    private let _children: [any DiagnosticsNodeProtocol]
    private let _properties: [any DiagnosticsNodeProtocol]

    /// **Dart Source:** `diagnostics.dart:3538-3539`
    public override var level: DiagnosticLevel { _level }

    /// **Dart Source:** `diagnostics.dart:3544`
    public override var value: Any? { _value }

    /// **Dart Source:** `diagnostics.dart:3546-3547`
    public override var allowTruncate: Bool { _allowTruncate }

    /// **Dart Source:** `diagnostics.dart:3549-3550`
    public override func getChildren() -> [any DiagnosticsNodeProtocol] {
        return _children
    }

    /// **Dart Source:** `diagnostics.dart:3552-3553`
    public override func getProperties() -> [any DiagnosticsNodeProtocol] {
        return _properties
    }

    /// **Dart Source:** `diagnostics.dart:3555-3556`
    public override func toDescription(parentConfiguration: TextTreeConfiguration?) -> String {
        return _description
    }
}
