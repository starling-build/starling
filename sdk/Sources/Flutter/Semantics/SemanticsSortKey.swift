// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Sort keys for accessibility traversal order sorting.
///
/// **Dart Source:** `packages/flutter/lib/src/semantics/semantics.dart`

// MARK: - SemanticsSortKey

/// Base class for all sort keys for accessibility traversal order sorting.
///
/// Sort keys are sorted by `name`, then by the comparison that the subclass
/// implements. If a sort key is specified, sort keys within the same semantic
/// group must all be of the same type.
///
/// Keys with no `name` are compared to other keys with no `name`, and will
/// be traversed before those with a `name`.
///
/// If no sort key is applied to a semantics node, then it will be ordered using
/// a platform dependent default algorithm.
///
/// See also:
///
///  * `OrdinalSortKey` for a sort key that sorts using an ordinal.
///
/// **Dart Source:** `semantics.dart:6236-6308`
/// **Original Name:** `SemanticsSortKey`
///
// DIFFERENCE FROM DART: Uses a base class instead of abstract class.
// REASON: Swift does not have abstract classes. A base class with `fatalError`
// in `doCompare` achieves the same contract: subclasses must override it.
//
// DIFFERENCE FROM DART: Conforms to `Comparable` via static `<` and `==` operators
// instead of implementing a `compareTo` method.
// REASON: Swift's `Comparable` protocol requires `<` operator. The `compareTo`
// logic is preserved in the `<` operator implementation.
public class SemanticsSortKey: Diagnosticable, Comparable {

  /// Creates a semantics sort key with an optional name.
  ///
  /// The name groups sort keys together before comparing via `doCompare`.
  ///
  /// **Dart Source:** `semantics.dart:6253-6255`
  /// **Original:** `const SemanticsSortKey({this.name})`
  public init(name: String? = nil) {
    self.name = name
  }

  /// An optional name that will group this sort key with other sort keys of the
  /// same `name`.
  ///
  /// Sort keys must have the same runtime type when compared.
  ///
  /// Keys with no `name` are compared to other keys with no `name`, and will
  /// be traversed before those with a `name`.
  ///
  /// **Dart Source:** `semantics.dart:6257-6264`
  public let name: String?

  /// Compares this sort key with another sort key of the same type.
  ///
  /// The argument is guaranteed to be of the same type as this object and have
  /// the same `name`.
  ///
  /// The method should return a negative number if this object comes earlier in
  /// the sort order than the argument; and a positive number if it comes later
  /// in the sort order. Returning zero causes the system to use default sort
  /// order.
  ///
  /// **Dart Source:** `semantics.dart:6291-6301`
  /// **Original:** `int doCompare(covariant SemanticsSortKey other)`
  ///
  // DIFFERENCE FROM DART: Uses `fatalError` instead of being an abstract method.
  // REASON: Swift does not have abstract classes. Subclasses must override this.
  func doCompare(_ other: SemanticsSortKey) -> Int {
    fatalError("Subclasses of SemanticsSortKey must override doCompare")
  }

  /// Compares this sort key to another, grouping by name first.
  ///
  /// Sort keys that don't have a name sort before those with a name.
  /// Keys with the same name group together and use `doCompare`.
  /// Keys with different names sort alphabetically by name.
  ///
  /// **Dart Source:** `semantics.dart:6266-6288`
  /// **Original:** `int compareTo(SemanticsSortKey other)`
  public func compareTo(_ other: SemanticsSortKey) -> Int {
    // Sort by name first and then subclass ordering.
    assert(
      type(of: self) == type(of: other),
      "Semantics sort keys can only be compared to other sort keys of the same type."
    )

    // Defer to the subclass implementation for ordering only if the names are
    // identical (or both null).
    if name == other.name {
      return doCompare(other)
    }

    // Keys that don't have a name are sorted together and come before those with
    // a name.
    if name == nil && other.name != nil {
      return -1
    } else if name != nil && other.name == nil {
      return 1
    }

    return name! < other.name! ? -1 : name! > other.name! ? 1 : 0
  }

  // MARK: - Comparable

  /// **Dart Source:** `semantics.dart:6266-6288`
  public static func < (lhs: SemanticsSortKey, rhs: SemanticsSortKey) -> Bool {
    return lhs.compareTo(rhs) < 0
  }

  /// **Dart Source:** `semantics.dart:6266-6288`
  public static func == (lhs: SemanticsSortKey, rhs: SemanticsSortKey) -> Bool {
    return lhs.compareTo(rhs) == 0
  }

  // MARK: - Diagnosticable

  /// **Dart Source:** `semantics.dart:6303-6307`
  public func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
    properties.add(StringProperty("name", name, defaultValue: nil))
  }
}

// MARK: - OrdinalSortKey

/// A `SemanticsSortKey` that sorts based on the `Double` value it is given.
///
/// The `OrdinalSortKey` compares itself with other `OrdinalSortKey`s
/// to sort based on the order it is given.
///
/// `OrdinalSortKey`s are sorted by the optional `name`, then by their `order`.
/// If the sort key is an `OrdinalSortKey`, then all the other
/// specified sort keys in the same semantics group must also be
/// `OrdinalSortKey`s.
///
/// Keys with no `name` are compared to other keys with no `name`, and will
/// be traversed before those with a `name`.
///
/// The ordinal value `order` is typically a whole number, though it can be
/// fractional, e.g. in order to fit between two other consecutive whole
/// numbers. The value must be finite (it cannot be `Double.nan`,
/// `Double.infinity`, or `-Double.infinity`).
///
/// **Dart Source:** `semantics.dart:6310-6357`
/// **Original Name:** `OrdinalSortKey`
public class OrdinalSortKey: SemanticsSortKey {

  /// Creates a semantics sort key that uses a `Double` as its key value.
  ///
  /// The `order` must be a finite number.
  ///
  /// **Dart Source:** `semantics.dart:6328-6334`
  /// **Original:** `const OrdinalSortKey(this.order, {super.name})`
  public init(_ order: Double, name: String? = nil) {
    assert(order > -.infinity, "OrdinalSortKey order must be greater than negative infinity")
    assert(order < .infinity, "OrdinalSortKey order must be less than infinity")
    self.order = order
    super.init(name: name)
  }

  /// Determines the placement of this key in a sequence of keys that defines
  /// the order in which this node is traversed by the platform's accessibility
  /// services.
  ///
  /// Lower values will be traversed first. Keys with the same `name` will be
  /// grouped together and sorted by name first, and then sorted by `order`.
  ///
  /// **Dart Source:** `semantics.dart:6336-6342`
  public let order: Double

  /// **Dart Source:** `semantics.dart:6344-6350`
  override func doCompare(_ other: SemanticsSortKey) -> Int {
    let other = other as! OrdinalSortKey
    if other.order == order {
      return 0
    }
    return order < other.order ? -1 : 1
  }

  // MARK: - Diagnosticable

  /// **Dart Source:** `semantics.dart:6352-6356`
  public override func debugFillProperties(_ properties: DiagnosticPropertiesBuilder) {
    super.debugFillProperties(properties)
    properties.add(DoubleProperty("order", order, defaultValue: nil))
  }
}
