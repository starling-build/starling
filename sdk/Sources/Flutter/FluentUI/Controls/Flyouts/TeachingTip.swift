// Ported from: fluent_ui teaching tip concept
//
// A teaching tip is a semi-persistent, content-rich flyout that provides
// contextual information. It can include a title, subtitle, body, close button,
// and optional action buttons.

import FlutterSwiftBridge

// MARK: - TeachingTip

/// A semi-persistent, content-rich flyout that provides contextual information
/// attached to a target widget.
///
/// Teaching tips are used to inform users about new or important features.
/// They can include a title, subtitle, body text, and action buttons.
///
/// Usage:
/// ```swift
/// TeachingTip(
///     target: myButton,
///     title: Text("New Feature"),
///     subtitle: Text("Try this out"),
///     body: Text("This button lets you do something cool."),
///     isOpen: showTip,
///     onClose: { setState { showTip = false } },
///     actions: [
///         Button(child: Text("Got it"), onPressed: { setState { showTip = false } })
///     ]
/// )
/// ```
public class TeachingTip: StatefulWidget {
    /// The target widget the tip points to.
    public let target: Widget

    /// The title of the teaching tip.
    public let title: Widget?

    /// The subtitle of the teaching tip.
    public let subtitle: Widget?

    /// Whether the teaching tip is currently shown.
    public let isOpen: Bool

    /// The placement relative to the target.
    public let placement: FlyoutPlacement

    /// Called when the close button is pressed.
    public let onClose: (() -> Void)?

    /// The body content of the teaching tip.
    public let body: Widget?

    /// Optional action buttons (e.g., "Got it" / "Next").
    public let actions: [Widget]?

    /// Creates a teaching tip.
    public init(
        key: (any Key)? = nil,
        target: Widget,
        title: Widget? = nil,
        subtitle: Widget? = nil,
        isOpen: Bool = false,
        placement: FlyoutPlacement = .auto,
        onClose: (() -> Void)? = nil,
        body: Widget? = nil,
        actions: [Widget]? = nil
    ) {
        self.target = target
        self.title = title
        self.subtitle = subtitle
        self.isOpen = isOpen
        self.placement = placement
        self.onClose = onClose
        self.body = body
        self.actions = actions
        super.init(key: key)
    }

    public override func createState() -> State<StatefulWidget> {
        return _TeachingTipState()
    }
}

// MARK: - _TeachingTipState

class _TeachingTipState: State<StatefulWidget> {
    private let _flyoutController = FlyoutController()
    private var _needsShowOnBuild = false

    private var teachingTip: TeachingTip {
        return widget as! TeachingTip
    }

    override func initState() {
        super.initState()
        // If already open at init time, defer showing until the first build
        // completes and the FlyoutController is attached.
        if teachingTip.isOpen {
            _needsShowOnBuild = true
        }
    }

    override func didUpdateWidget(_ oldWidget: StatefulWidget) {
        super.didUpdateWidget(oldWidget)
        let oldTip = oldWidget as! TeachingTip
        if teachingTip.isOpen && !oldTip.isOpen {
            _deferShow()
        } else if !teachingTip.isOpen && oldTip.isOpen {
            _flyoutController.closeFlyout()
        }
    }

    /// Shows on the next frame, not now: both places that ask to show are
    /// inside a build (the first build, or `didUpdateWidget`), where the
    /// target below is not attached yet and the overlay cannot be changed.
    /// Called from within a build, `_showTip` returned at its attach guard
    /// and the tip never appeared. A one-shot ticker is the frame boundary.
    private var _deferTicker: Ticker?
    private func _deferShow() {
        _deferTicker?.dispose()
        let ticker = Ticker { [weak self] _ in
            guard let self else { return }
            self._deferTicker?.stop()
            self._deferTicker?.dispose()
            self._deferTicker = nil
            self._showTip()
        }
        _deferTicker = ticker
        _ = ticker.start()
    }

    override func dispose() {
        _deferTicker?.dispose()
        _flyoutController.closeFlyout()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        // Deferred show: on the frame after the first build, once the
        // controller is attached.
        if _needsShowOnBuild {
            _needsShowOnBuild = false
            _deferShow()
        }

        return FlyoutTarget(
            controller: _flyoutController,
            child: teachingTip.target
        )
    }

    private func _showTip() {
        guard _flyoutController.isAttached else { return }
        if _flyoutController.isOpen { return }

        _flyoutController.showFlyout(
            builder: { [weak self] context in
                guard let self = self else {
                    return SizedBox(width: 0, height: 0)
                }
                return self._buildTipContent(context)
            },
            barrierDismissible: false,
            placement: teachingTip.placement,
            additionalOffset: 12.0
        )
    }

    private func _buildTipContent(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let res = theme.resources

        // Build the column children
        var columnChildren: [Widget] = []

        // Header row: title + close button
        let titleWidget: Widget = teachingTip.title ?? SizedBox(width: 0, height: 0)
        let hasTitle = teachingTip.title != nil

        let closeButton: Widget = HoverButton(
            builder: { context, states in
                let color: Color = states.isHovered
                    ? res.textFillColorSecondary
                    : res.textFillColorPrimary
                return FluentGlyph(.dismiss, size: 12, color: color)
            },
            onPressed: { [weak self] in
                self?.teachingTip.onClose?()
            }
        )

        if hasTitle || teachingTip.onClose != nil {
            let headerChildren: [Widget] = [
                Expanded(
                    child: DefaultTextStyle(
                        style: TextStyle(
                            color: res.textFillColorPrimary,
                            fontSize: 14,
                            fontWeight: .w600
                        ),
                        child: titleWidget
                    )
                ),
                teachingTip.onClose != nil
                    ? SizedBox(width: 24, height: 24, child: Center(child: closeButton))
                    : SizedBox(width: 0, height: 0)
            ]

            columnChildren.append(
                Row(
                    mainAxisSize: .min,
                    crossAxisAlignment: .start,
                    children: headerChildren
                )
            )
        }

        // Subtitle
        if let subtitle = teachingTip.subtitle {
            columnChildren.append(
                Padding(
                    padding: EdgeInsets(top: 4),
                    child: DefaultTextStyle(
                        style: TextStyle(
                            color: res.textFillColorSecondary,
                            fontSize: 12
                        ),
                        child: subtitle
                    )
                )
            )
        }

        // Body
        if let body = teachingTip.body {
            columnChildren.append(
                Padding(
                    padding: EdgeInsets(top: 8),
                    child: DefaultTextStyle(
                        style: TextStyle(
                            color: res.textFillColorPrimary,
                            fontSize: 13
                        ),
                        child: body
                    )
                )
            )
        }

        // Actions row
        if let actions = teachingTip.actions, !actions.isEmpty {
            columnChildren.append(
                Padding(
                    padding: EdgeInsets(top: 12),
                    child: Row(
                        mainAxisAlignment: .end,
                        mainAxisSize: .min,
                        children: actions.enumerated().map { index, action in
                            if index > 0 {
                                return Padding(
                                    padding: EdgeInsets(left: 8),
                                    child: action
                                ) as Widget
                            }
                            return action
                        }
                    )
                )
            )
        }

        let content: Widget = Column(
            mainAxisSize: .min,
            crossAxisAlignment: .start,
            children: columnChildren
        )

        return FlyoutContent(
            child: content,
            padding: EdgeInsets(all: 12),
            constraints: BoxConstraints(minWidth: 200, maxWidth: 336)
        )
    }
}
