// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The pieces every gallery page is built from, shaped like the WinUI 3
// Gallery's: a page is a title, a paragraph and a list of examples; an
// example is a card with the live control on the left and its options on
// the right; a category is a grid of tiles. Keeping these here means a
// control page is a dozen lines and reads the same as the one beside it.

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons
import Foundation

// MARK: - LocalState

/// A little state for a sample that has to react — a toggle, a slider — so
/// the sample can be written inline instead of as a StatefulWidget of its
/// own. The builder gets the value and a setter.
final class LocalState<T>: StatefulWidget {
    let initial: T
    let builder: (T, @escaping (T) -> Void) -> Widget

    init(_ initial: T, builder: @escaping (T, @escaping (T) -> Void) -> Widget) {
        self.initial = initial
        self.builder = builder
        super.init()
    }

    override func createState() -> State<StatefulWidget> { _LocalStateState<T>() }
}

final class _LocalStateState<T>: State<StatefulWidget> {
    private var _value: T?

    override func build(_ context: any BuildContext) -> Widget {
        let w = widget as! LocalState<T>
        if _value == nil { _value = w.initial }
        return w.builder(_value!) { [weak self] v in
            self?.setState { self?._value = v }
        }
    }
}

// MARK: - AutoTrigger

/// Runs `action` a moment after mount when `FLUENT_GALLERY_AUTO=1` is set —
/// how a screenshot script sees a flyout, a menu or a dialog open without a
/// pointer to click with. Off, it is its child and nothing else.
final class AutoTrigger: StatefulWidget {
    let delay: Duration
    let action: (any BuildContext) -> Void
    let child: Widget

    init(delay: Duration = .milliseconds(1500), action: @escaping (any BuildContext) -> Void, child: Widget) {
        self.delay = delay
        self.action = action
        self.child = child
        super.init()
    }

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["FLUENT_GALLERY_AUTO"] == "1"
    }

    override func createState() -> State<StatefulWidget> { _AutoTriggerState() }
}

final class _AutoTriggerState: State<StatefulWidget>, TickerProvider {
    private var _controller: AnimationController?
    private var trigger: AutoTrigger { widget as! AutoTrigger }

    func createTicker(_ onTick: @escaping TickerCallback) -> Ticker { Ticker(onTick) }

    override func initState() {
        super.initState()
        guard AutoTrigger.enabled else { return }
        let c = AnimationController(duration: trigger.delay, vsync: self)
        c.addStatusListener { [weak self] status in
            guard let self, status == .completed, let ctx = self.context else { return }
            self.trigger.action(ctx)
        }
        _controller = c
        _ = c.forward()
    }

    override func dispose() {
        _controller?.dispose()
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget { trigger.child }
}

// MARK: - Sample and SamplePage

/// One example on a control page.
struct Sample {
    let title: String
    let options: [Widget]
    let child: Widget

    init(_ title: String, options: [Widget] = [], child: Widget) {
        self.title = title
        self.options = options
        self.child = child
    }
}

/// A control page: title, description, examples. The layout is the WinUI 3
/// Gallery's — a Title, a Body paragraph, then each example under a Body
/// Strong header.
final class SamplePage: StatelessWidget {
    let title: String
    let description: String
    let samples: [Sample]

    init(_ title: String, _ description: String, samples: [Sample]) {
        self.title = title
        self.description = description
        self.samples = samples
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let t = FluentTheme.of(context).typography
        return SingleChildScrollView(
            padding: EdgeInsets(left: 36, top: 28, right: 36, bottom: 36),
            child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.xl) {
                Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    Text(title, style: t.title)
                    Text(description, style: t.body)
                }
                for s in samples {
                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                        Text(s.title, style: t.bodyStrong)
                        ExampleCard(child: s.child, options: s.options)
                    }
                }
            }
        )
    }
}

// MARK: - ExampleCard

/// The card an example lives in: the sample at the left on the card fill,
/// and, when there are any, its options in a column at the right behind a
/// hairline — the WinUI Gallery's "ControlExample".
final class ExampleCard: StatelessWidget {
    let child: Widget
    let options: [Widget]

    init(child: Widget, options: [Widget] = []) {
        self.child = child
        self.options = options
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let r = theme.resources
        return DecoratedBox(
            decoration: BoxDecoration(
                color: r.cardBackgroundFillColorDefault,
                border: Border.all(color: r.cardStrokeColorDefault, width: FluentStrokeWidth.thin),
                borderRadius: FluentCorners.overlayRadius),
            child: ClipRRect(
                borderRadius: FluentCorners.overlayRadius,
                child: Row(crossAxisAlignment: .start) {
                    Expanded {
                        Padding(padding: EdgeInsets(all: FluentSpacing.xxl)) {
                            Align(alignment: Alignment.topLeft) { child }
                        }
                    }
                    if !options.isEmpty {
                        DecoratedBox(
                            decoration: BoxDecoration(
                                color: r.layerFillColorDefault,
                                border: Border(left: BorderSide(
                                    color: r.dividerStrokeColorDefault,
                                    width: FluentStrokeWidth.thin))),
                            child: SizedBox(
                                width: 260,
                                child: Padding(padding: EdgeInsets(all: FluentSpacing.l)) {
                                    Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                                        Text("Options", style: theme.typography.bodyStrong)
                                        options
                                    }
                                }))
                    }
                }
            )
        )
    }
}

// MARK: - GalleryTile

/// One entry in a category grid: icon plate, name, one-line description.
final class GalleryTile: StatelessWidget {
    let icon: IconData
    let title: String
    let subtitle: String
    let onTap: () -> Void

    init(icon: IconData, title: String, subtitle: String, onTap: @escaping () -> Void) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.onTap = onTap
        super.init()
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let r = theme.resources
        let accent = theme.accentColor.defaultBrushFor(theme.brightness)
        return HoverButton(
            builder: { _, states in
                let hot = states.isHovered || states.isPressed
                return DecoratedBox(
                    decoration: BoxDecoration(
                        color: hot ? r.controlFillColorSecondary : r.cardBackgroundFillColorDefault,
                        border: Border.all(color: r.cardStrokeColorDefault, width: FluentStrokeWidth.thin),
                        borderRadius: FluentCorners.controlRadius),
                    child: SizedBox(
                        width: 340, height: 92,
                        child: Padding(padding: EdgeInsets(all: FluentSpacing.m)) {
                            Row(crossAxisAlignment: .center, spacing: FluentSpacing.m) {
                                DecoratedBox(
                                    decoration: BoxDecoration(
                                        color: r.subtleFillColorSecondary,
                                        borderRadius: FluentCorners.controlRadius),
                                    child: SizedBox(
                                        width: 56, height: 56,
                                        child: Center(child: Icon(self.icon, size: 26, color: accent))))
                                Expanded {
                                    Column(mainAxisAlignment: .center, crossAxisAlignment: .start,
                                           spacing: FluentSpacing.xxs) {
                                        Text(self.title, style: theme.typography.bodyStrong,
                                             overflow: .ellipsis, maxLines: 1)
                                        Text(self.subtitle, style: theme.typography.caption,
                                             overflow: .ellipsis, maxLines: 2)
                                    }
                                }
                            }
                        }))
            },
            onPressed: onTap)
    }
}

// MARK: - Small bits

/// A row of label + control, for an options column.
func optionRow(_ label: String, _ context: any BuildContext, _ control: Widget) -> Widget {
    let t = FluentTheme.of(context).typography
    return Column(crossAxisAlignment: .start, spacing: FluentSpacing.xs) {
        Text(label, style: t.caption)
        control
    }
}

/// A coloured square with a caption under it.
func swatchTile(_ color: Color, label: String, _ context: any BuildContext,
                size: Double = 40, radius: Double = FluentCorners.control,
                ring: Color? = nil) -> Widget {
    let t = FluentTheme.of(context).typography
    return Column(spacing: FluentSpacing.xs) {
        DecoratedBox(
            decoration: BoxDecoration(
                color: color,
                border: ring.map { Border.all(color: $0, width: FluentStrokeWidth.thick) },
                borderRadius: BorderRadius.circular(radius)),
            child: SizedBox(width: max(size, 1), height: max(size, 1)))
        Text(label, style: t.caption)
    }
}

/// Milliseconds of a Duration, for labels.
func milliseconds(_ d: Duration) -> Int {
    let (s, attos) = d.components
    return Int(s) * 1000 + Int(attos / 1_000_000_000_000_000)
}
#endif
