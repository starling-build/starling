// Ported from: fluent_ui/lib/src/controls/navigation/navigation_view/style.dart
//
// Page transition animations used by NavigationView when switching between pages.

import FlutterSwiftBridge

// MARK: - NavigationPageTransition

/// Defines the type of page transition animation.
public enum NavigationPageTransition {
    /// No transition, content swaps instantly.
    case none

    /// An entrance transition: slide up + fade in.
    case entrance

    /// A drill-in transition: slight scale up + fade in.
    case drillIn

    /// A horizontal slide transition.
    case horizontalSlide
}

// MARK: - EntrancePageTransition

/// An entrance-style page transition that slides content up and fades it in.
///
/// Used as the default page transition in NavigationView.
///
/// Usage:
/// ```swift
/// EntrancePageTransition(
///     child: pageContent
/// )
/// ```
public class EntrancePageTransition: ImplicitlyAnimatedWidget {
    /// The child widget to transition.
    public let child: Widget

    /// Creates an entrance page transition.
    public init(
        key: (any Key)? = nil,
        child: Widget,
        duration: Duration = FluentMotion.directEntrance.duration,
        curve: any Curve = FluentMotion.directEntrance.curve
    ) {
        self.child = child
        super.init(key: key, curve: curve, duration: duration)
    }

    public override func createState() -> State<StatefulWidget> {
        return _EntrancePageTransitionState()
    }
}

class _EntrancePageTransitionState: AnimatedWidgetBaseState {
    private var _opacityTween: Tween<Double>?
    private var _offsetTween: Tween<Double>?

    private var transitionWidget: EntrancePageTransition {
        return widget as! EntrancePageTransition
    }

    override func initTweens() {
        // Start fully visible, no offset
        _opacityTween = Tween<Double>(begin: 1.0, end: 1.0)
        _offsetTween = Tween<Double>(begin: 0.0, end: 0.0)
    }

    override func updateTweens() -> Bool {
        // When widget changes, animate from slightly below + transparent to normal
        _opacityTween = Tween<Double>(begin: 0.0, end: 1.0)
        _offsetTween = Tween<Double>(begin: 40.0, end: 0.0)
        return true
    }

    override func build(_ context: any BuildContext) -> Widget {
        let opacity = _opacityTween?.evaluate(animation) ?? 1.0
        let offset = _offsetTween?.evaluate(animation) ?? 0.0

        let child: Widget = transitionWidget.child

        if offset == 0.0 && opacity == 1.0 {
            return child
        }

        var result: Widget = child

        if opacity < 1.0 {
            result = Opacity(opacity: opacity, child: result)
        }

        if offset != 0.0 {
            result = Transform(
                translate: Offset(0, offset),
                child: result
            )
        }

        return result
    }
}

// MARK: - DrillInPageTransition

/// A drill-in page transition that scales content up slightly and fades it in.
///
/// Typically used when navigating deeper into a hierarchy.
public class DrillInPageTransition: ImplicitlyAnimatedWidget {
    /// The child widget to transition.
    public let child: Widget

    /// Creates a drill-in page transition.
    public init(
        key: (any Key)? = nil,
        child: Widget,
        duration: Duration = FluentMotion.directEntrance.duration,
        curve: any Curve = FluentMotion.directEntrance.curve
    ) {
        self.child = child
        super.init(key: key, curve: curve, duration: duration)
    }

    public override func createState() -> State<StatefulWidget> {
        return _DrillInPageTransitionState()
    }
}

class _DrillInPageTransitionState: AnimatedWidgetBaseState {
    private var _opacityTween: Tween<Double>?
    private var _scaleTween: Tween<Double>?

    private var transitionWidget: DrillInPageTransition {
        return widget as! DrillInPageTransition
    }

    override func initTweens() {
        _opacityTween = Tween<Double>(begin: 1.0, end: 1.0)
        _scaleTween = Tween<Double>(begin: 1.0, end: 1.0)
    }

    override func updateTweens() -> Bool {
        _opacityTween = Tween<Double>(begin: 0.0, end: 1.0)
        _scaleTween = Tween<Double>(begin: 0.95, end: 1.0)
        return true
    }

    override func build(_ context: any BuildContext) -> Widget {
        let opacity = _opacityTween?.evaluate(animation) ?? 1.0
        let scale = _scaleTween?.evaluate(animation) ?? 1.0

        let child: Widget = transitionWidget.child

        if scale == 1.0 && opacity == 1.0 {
            return child
        }

        var result: Widget = child

        if opacity < 1.0 {
            result = Opacity(opacity: opacity, child: result)
        }

        if scale != 1.0 {
            result = Transform(scale: scale, child: result)
        }

        return result
    }
}

// MARK: - HorizontalSlidePageTransition

/// A horizontal slide page transition.
///
/// Slides content in from the right and fades it in simultaneously.
public class HorizontalSlidePageTransition: ImplicitlyAnimatedWidget {
    /// The child widget to transition.
    public let child: Widget

    /// Creates a horizontal slide page transition.
    public init(
        key: (any Key)? = nil,
        child: Widget,
        duration: Duration = FluentMotion.directEntrance.duration,
        curve: any Curve = FluentMotion.directEntrance.curve
    ) {
        self.child = child
        super.init(key: key, curve: curve, duration: duration)
    }

    public override func createState() -> State<StatefulWidget> {
        return _HorizontalSlidePageTransitionState()
    }
}

class _HorizontalSlidePageTransitionState: AnimatedWidgetBaseState {
    private var _opacityTween: Tween<Double>?
    private var _offsetTween: Tween<Double>?

    private var transitionWidget: HorizontalSlidePageTransition {
        return widget as! HorizontalSlidePageTransition
    }

    override func initTweens() {
        _opacityTween = Tween<Double>(begin: 1.0, end: 1.0)
        _offsetTween = Tween<Double>(begin: 0.0, end: 0.0)
    }

    override func updateTweens() -> Bool {
        _opacityTween = Tween<Double>(begin: 0.0, end: 1.0)
        _offsetTween = Tween<Double>(begin: 100.0, end: 0.0)
        return true
    }

    override func build(_ context: any BuildContext) -> Widget {
        let opacity = _opacityTween?.evaluate(animation) ?? 1.0
        let offset = _offsetTween?.evaluate(animation) ?? 0.0

        let child: Widget = transitionWidget.child

        if offset == 0.0 && opacity == 1.0 {
            return child
        }

        var result: Widget = child

        if opacity < 1.0 {
            result = Opacity(opacity: opacity, child: result)
        }

        if offset != 0.0 {
            result = Transform(
                translate: Offset(offset, 0),
                child: result
            )
        }

        return result
    }
}
