// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// MARK: - InheritedModel

/// An `InheritedWidget` that's intended to be used as the base class for models
/// whose dependents may only depend on one part or "aspect" of the overall model.
///
/// The type parameter `T` is the type of the model aspect objects.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/inherited_model.dart:121-216`
open class InheritedModel<T: Hashable>: InheritedWidget {

    /// Creates an inherited widget that supports dependencies qualified by
    /// "aspects", i.e. a descendant widget can indicate that it should
    /// only be rebuilt if a specific aspect of the model changes.
    ///
    /// **Dart Source:** `inherited_model.dart:125`
    public override init(key: (any Key)? = nil, child: Widget) {
        super.init(key: key, child: child)
    }

    /// Creates the `InheritedModelElement` for this widget.
    ///
    /// **Dart Source:** `inherited_model.dart:128`
    open func createModelElement() -> InheritedModelElement<T> {
        return InheritedModelElement<T>(self)
    }

    /// Return true if the changes between this model and `oldWidget` match any
    /// of the `dependencies`.
    ///
    /// **Dart Source:** `inherited_model.dart:133`
    open func updateShouldNotifyDependent(_ oldWidget: InheritedModel<T>, dependencies: Set<T>) -> Bool {
        fatalError("Subclasses must override updateShouldNotifyDependent")
    }

    /// Returns true if this model supports the given `aspect`.
    ///
    /// Returns true by default: this model supports all aspects.
    ///
    /// **Dart Source:** `inherited_model.dart:143`
    open func isSupportedAspect(_ aspect: AnyHashable) -> Bool {
        return true
    }

    /// Finds models of the given `modelType` in the ancestor chain of `context`
    /// that support the given `aspect`.
    ///
    /// The `result` will be a list of all of context's ancestors of `modelType`
    /// concluding with the one that supports the specified model `aspect`.
    ///
    /// **Dart Source:** `inherited_model.dart:147-175`
    private static func findModels<M: InheritedModel<T>>(
        _ context: any BuildContext,
        modelType: M.Type,
        aspect: AnyHashable,
        results: inout [InheritedElement]
    ) {
        guard let model = context.getElementForInheritedWidgetOfExactType(M.self) else {
            return
        }

        results.append(model)

        assert(model.widget is M)
        let modelWidget = model.widget as! M
        if modelWidget.isSupportedAspect(aspect) {
            return
        }

        var modelParent: Element?
        model.visitAncestorElements { ancestor in
            modelParent = ancestor
            return false
        }
        guard let parent = modelParent else {
            return
        }

        findModels(parent, modelType: modelType, aspect: aspect, results: &results)
    }

    /// Makes `context` dependent on the specified `aspect` of an `InheritedModel`
    /// of type `M`.
    ///
    /// When the given `aspect` of the model changes, the `context` will be
    /// rebuilt. The `updateShouldNotifyDependent` method must determine if a
    /// change in the model widget corresponds to an `aspect` value.
    ///
    /// If `aspect` is nil this method is the same as
    /// `context.dependOnInheritedWidgetOfExactType(M.self)`.
    ///
    /// If no ancestor of type `M` exists, nil is returned.
    ///
    /// **Dart Source:** `inherited_model.dart:192-215`
    public static func inheritFrom<M: InheritedModel<T>>(
        _ context: any BuildContext,
        modelType: M.Type,
        aspect: AnyHashable? = nil
    ) -> M? {
        if aspect == nil {
            return context.dependOnInheritedWidgetOfExactType(M.self)
        }

        // Create a dependency on all of the type M ancestor models up until
        // a model is found for which isSupportedAspect(aspect) is true.
        var models: [InheritedElement] = []
        findModels(context, modelType: modelType, aspect: aspect!, results: &models)
        if models.isEmpty {
            return nil
        }

        let lastModel = models.last!
        for model in models {
            let value = context.dependOnInheritedElement(model, aspect: aspect) as! M
            if model === lastModel {
                return value
            }
        }

        assertionFailure("Unreachable")
        return nil
    }
}

// MARK: - InheritedModelElement

/// An `Element` that uses an `InheritedModel` as its configuration.
///
/// **Dart Source:** `packages/flutter/lib/src/widgets/inherited_model.dart:219-249`
public class InheritedModelElement<T: Hashable>: InheritedElement {

    /// Creates an element that uses the given widget as its configuration.
    ///
    /// **Dart Source:** `inherited_model.dart:221`
    public init(_ widget: InheritedModel<T>) {
        super.init(widget)
    }

    /// **Dart Source:** `inherited_model.dart:224-236`
    public override func updateDependencies(_ dependent: Element, aspect: AnyHashable?) {
        let dependencies = (getDependencies(dependent) as? _AspectSet<T>)?.aspects
        if let deps = dependencies, deps.isEmpty {
            return
        }

        if aspect == nil {
            setDependencies(dependent, _AspectSet(Set<T>()))
        } else {
            let aspectValue = aspect!.base as! T
            var deps = dependencies ?? Set<T>()
            deps.insert(aspectValue)
            setDependencies(dependent, _AspectSet(deps))
        }
    }

    /// **Dart Source:** `inherited_model.dart:239-248`
    public override func notifyDependent(_ oldWidget: InheritedWidget, _ dependent: Element) {
        let dependencies = (getDependencies(dependent) as? _AspectSet<T>)?.aspects
        guard let dependencies = dependencies else {
            return
        }
        if dependencies.isEmpty ||
            (widget as! InheritedModel<T>).updateShouldNotifyDependent(
                oldWidget as! InheritedModel<T>, dependencies: dependencies
            ) {
            dependent.didChangeDependencies()
        }
    }
}

/// The aspects an element depends on, as the `AnyObject` the dependency
/// slot holds. A box of our own rather than `Set as AnyObject`: that spelling
/// bridges through NSSet, the legacy Foundation layer.
private final class _AspectSet<T: Hashable> {
    let aspects: Set<T>
    init(_ aspects: Set<T>) { self.aspects = aspects }
}
