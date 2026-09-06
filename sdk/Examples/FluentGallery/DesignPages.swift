// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The "Design guidance" pages: the tokens themselves, drawn. Typography,
// colour, geometry, spacing, materials, elevation, motion and icons — each
// page reads its values from `FluentUI/Styles`, so if a page looks wrong
// the token is wrong, not the page.

#if os(Linux)
import Flutter
import FlutterSwiftBridge
import FluentSystemIcons

// MARK: - Typography

final class TypographyPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let t = FluentTheme.of(context).typography
        let ramp: [(String, Flutter.TextStyle?, String)] = [
            ("Display", t.display, "68 / 92, Semibold"),
            ("Title Large", t.titleLarge, "40 / 52, Semibold"),
            ("Title", t.title, "28 / 36, Semibold"),
            ("Subtitle", t.subtitle, "20 / 28, Semibold"),
            ("Body Large Strong", t.bodyLargeStrong, "18 / 24, Semibold"),
            ("Body Large", t.bodyLarge, "18 / 24, Regular"),
            ("Body Strong", t.bodyStrong, "14 / 20, Semibold"),
            ("Body", t.body, "14 / 20, Regular"),
            ("Caption", t.caption, "12 / 16, Regular"),
        ]
        return SamplePage(
            "Typography",
            "Windows 11's type ramp: Segoe UI Variable's nine styles, set here in Selawik, Microsoft's metric-compatible open substitute. Regular for most text, Semibold for titles; there is no Bold and no Italic in the ramp.",
            samples: [
                Sample("The ramp", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.m) {
                    for (name, style, spec) in ramp {
                        Row(crossAxisAlignment: .end, spacing: FluentSpacing.l) {
                            Expanded { Text(name, style: style) }
                            Text(spec, style: t.caption)
                        }
                    }
                }),
                Sample("Rules", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    Text("Minimum 12px Regular, 14px Semibold — smaller is illegible in some languages.", style: t.body)
                    Text("Sentence case for all UI text, including titles.", style: t.body)
                    Text("Left-align by default; centre only under icons. Truncate with an ellipsis.", style: t.body)
                    Text("Keep to 50–60 characters per line.", style: t.body)
                }),
            ])
    }
}

// MARK: - Color

final class ColorPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let r = theme.resources
        let a = theme.accentColor
        let brush = a.defaultBrushFor(theme.brightness)
        let groups: [(String, [(String, Color)])] = [
            ("Text", [
                ("TextFillColorPrimary", r.textFillColorPrimary),
                ("TextFillColorSecondary", r.textFillColorSecondary),
                ("TextFillColorTertiary", r.textFillColorTertiary),
                ("TextFillColorDisabled", r.textFillColorDisabled),
                ("TextOnAccentFillColorPrimary", r.textOnAccentFillColorPrimary),
            ]),
            ("Control fill", [
                ("ControlFillColorDefault", r.controlFillColorDefault),
                ("ControlFillColorSecondary", r.controlFillColorSecondary),
                ("ControlFillColorTertiary", r.controlFillColorTertiary),
                ("ControlFillColorDisabled", r.controlFillColorDisabled),
                ("ControlStrongFillColorDefault", r.controlStrongFillColorDefault),
                ("SubtleFillColorSecondary", r.subtleFillColorSecondary),
                ("SubtleFillColorTertiary", r.subtleFillColorTertiary),
            ]),
            ("Stroke", [
                ("ControlStrokeColorDefault", r.controlStrokeColorDefault),
                ("ControlStrokeColorSecondary", r.controlStrokeColorSecondary),
                ("ControlStrongStrokeColorDefault", r.controlStrongStrokeColorDefault),
                ("CardStrokeColorDefault", r.cardStrokeColorDefault),
                ("DividerStrokeColorDefault", r.dividerStrokeColorDefault),
                ("SurfaceStrokeColorFlyout", r.surfaceStrokeColorFlyout),
                ("FocusStrokeColorOuter", r.focusStrokeColorOuter),
            ]),
            ("Background", [
                ("SolidBackgroundFillColorBase", r.solidBackgroundFillColorBase),
                ("SolidBackgroundFillColorSecondary", r.solidBackgroundFillColorSecondary),
                ("SolidBackgroundFillColorTertiary", r.solidBackgroundFillColorTertiary),
                ("SolidBackgroundFillColorQuarternary", r.solidBackgroundFillColorQuarternary),
                ("LayerFillColorDefault", r.layerFillColorDefault),
                ("CardBackgroundFillColorDefault", r.cardBackgroundFillColorDefault),
                ("SmokeFillColorDefault", r.smokeFillColorDefault),
            ]),
            ("System", [
                ("SystemFillColorSuccess", r.systemFillColorSuccess),
                ("SystemFillColorCaution", r.systemFillColorCaution),
                ("SystemFillColorCritical", r.systemFillColorCritical),
                ("SystemFillColorNeutral", r.systemFillColorNeutral),
                ("SystemFillColorSuccessBackground", r.systemFillColorSuccessBackground),
                ("SystemFillColorCautionBackground", r.systemFillColorCautionBackground),
                ("SystemFillColorCriticalBackground", r.systemFillColorCriticalBackground),
            ]),
        ]
        var samples: [Sample] = [
            Sample("Accent — the default blue and its shades; controls use \(theme.brightness == .dark ? "Light 2" : "Dark 1")",
                   child: Row(spacing: FluentSpacing.s) {
                for (name, c) in [("Light 3", a.light3), ("Light 2", a.light2), ("Light 1", a.light1),
                                  ("Base", a.normal), ("Dark 1", a.dark1), ("Dark 2", a.dark2), ("Dark 3", a.dark3)] {
                    swatchTile(c, label: name, context, size: 48,
                               ring: c == brush ? r.textFillColorPrimary : nil)
                }
                SizedBox(width: FluentSpacing.l)
                DecoratedBox(
                    decoration: BoxDecoration(color: brush, borderRadius: FluentCorners.controlRadius),
                    child: Padding(padding: EdgeInsets(left: 12, top: 6, right: 12, bottom: 6)) {
                        Text("On accent", style: theme.typography.body?.copyWith(
                            color: r.textOnAccentFillColorPrimary))
                    })
            }),
        ]
        for (group, tokens) in groups {
            samples.append(Sample(group, child: Wrap(spacing: FluentSpacing.m, runSpacing: FluentSpacing.m) {
                for (name, color) in tokens { _token(name, color, context) }
            }))
        }
        return SamplePage(
            "Color",
            "WinUI's resource dictionary — the 88 named colours every control reads — with the light or dark value for the current theme. Most are translucent and drawn here over the page, which is how they are meant to be seen.",
            samples: samples)
    }

    private func _token(_ name: String, _ color: Color, _ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        return SizedBox(width: 236, child: Row(spacing: FluentSpacing.s) {
            DecoratedBox(
                decoration: BoxDecoration(
                    color: color,
                    border: Border.all(color: theme.resources.controlStrokeColorDefault, width: 1),
                    borderRadius: FluentCorners.controlRadius),
                child: SizedBox(width: 32, height: 32))
            Expanded {
                Text(name, style: theme.typography.caption, overflow: .ellipsis, maxLines: 2)
            }
        })
    }
}

// MARK: - Geometry

final class GeometryPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let r = theme.resources
        let corners: [(String, Double)] = [
            ("control 4", FluentCorners.control), ("overlay 8", FluentCorners.overlay),
            ("xxLarge 12", FluentCorners.xxLarge), ("xxxLarge 16", FluentCorners.xxxLarge),
            ("circular", FluentCorners.circular),
        ]
        let strokes: [(String, Double)] = [
            ("thin 1", FluentStrokeWidth.thin), ("thick 2", FluentStrokeWidth.thick),
            ("thicker 3", FluentStrokeWidth.thicker), ("thickest 4", FluentStrokeWidth.thickest),
        ]
        return SamplePage(
            "Geometry",
            "Windows 11 rounds three ways: 8px on top-level containers (windows, flyouts, dialogs), 4px on in-page elements (buttons, list backplates, bars, tooltips), and not at all where straight edges meet or a window is snapped or maximized.",
            samples: [
                Sample("Corner radii", child: Row(crossAxisAlignment: .end, spacing: FluentSpacing.l) {
                    for (name, radius) in corners {
                        swatchTile(r.controlStrongFillColorDefault, label: name, context,
                                   size: 56, radius: radius)
                    }
                }),
                Sample("Stroke widths", child: Row(crossAxisAlignment: .end, spacing: FluentSpacing.l) {
                    for (name, w) in strokes {
                        Column(spacing: FluentSpacing.xs) {
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    border: Border.all(color: r.controlStrongStrokeColorDefault, width: w),
                                    borderRadius: FluentCorners.controlRadius),
                                child: SizedBox(width: 56, height: 56))
                            Text(name, style: theme.typography.caption)
                        }
                    }
                }),
            ])
    }
}

// MARK: - Spacing

final class SpacingPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let accent = theme.accentColor.defaultBrushFor(theme.brightness)
        let steps: [(String, Double)] = [
            ("xxs 2", FluentSpacing.xxs), ("xs 4", FluentSpacing.xs), ("sNudge 6", FluentSpacing.sNudge),
            ("s 8", FluentSpacing.s), ("mNudge 10", FluentSpacing.mNudge), ("m 12", FluentSpacing.m),
            ("l 16", FluentSpacing.l), ("xl 20", FluentSpacing.xl), ("xxl 24", FluentSpacing.xxl),
            ("xxxl 32", FluentSpacing.xxxl),
        ]
        let rules: [(String, Double)] = [
            ("between controls", FluentSpacing.betweenControls),
            ("control to label", FluentSpacing.controlToLabel),
            ("surface edge to text", FluentSpacing.surfaceInset),
            ("control height", FluentSpacing.controlHeight),
            ("minimum target", FluentSpacing.minimumTarget),
        ]
        return SamplePage(
            "Spacing",
            "The Fluent 2 spacing ramp, on a 4px grid, and the rules Windows states in it: 8 between buttons, 12 between a control and its label, 16 from a surface's edge to its text, 40 for anything a finger must hit.",
            samples: [
                Sample("The ramp", child: Row(crossAxisAlignment: .end, spacing: FluentSpacing.m) {
                    for (name, step) in steps {
                        swatchTile(accent, label: name, context, size: step, radius: 0)
                    }
                }),
                Sample("Windows layout rules", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    for (name, v) in rules {
                        Row(spacing: FluentSpacing.m) {
                            SizedBox(width: 180, child: Text(name, style: theme.typography.body))
                            DecoratedBox(
                                decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                                child: SizedBox(width: v * 4, height: 12))
                            Text("\(Int(v))", style: theme.typography.caption)
                        }
                    }
                }),
            ])
    }
}

// MARK: - Materials

final class MaterialsPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let t = theme.typography
        let stripes: [Color] = [
            Color(0xFFE81123), Color(0xFFF7630C), Color(0xFFFFB900), Color(0xFF107C10),
            Color(0xFF0078D4), Color(0xFF744DA9), Color(0xFFE3008C), Color(0xFF00B7C3),
        ]
        let label: (String) -> Widget = { text in Center(child: Text(text, style: t.bodyStrong)) }
        let backdrop = Stack {
            Positioned(fill: (), child: Row {
                for c in stripes { Expanded(child: ColoredBox(color: c, child: SizedBox(expand: ()))) }
            })
            Positioned(fill: (), child: Column(mainAxisAlignment: .spaceEvenly) {
                for _ in 0..<5 {
                    Text("the quick brown fox jumps over the lazy dog 0123456789",
                         style: t.body?.copyWith(color: Color(0xFF000000)))
                }
            })
        }
        // Bound first: `for x in [...] as [T] {` parses the brace as a trailing
        // closure on the cast.
        let wallpapers: [(String, Color?)] = [
            ("none", nil), ("blue", Color(0xFF3B6FB6)), ("sunset", Color(0xFFC46A2B)),
            ("forest", Color(0xFF2E7D4F)), ("plum", Color(0xFF6B3FA0)),
        ]
        let recipes: [(String, FluentMaterialRecipe)] = [
            ("Acrylic default", FluentMaterialRecipe.acrylicDefault(theme.brightness)),
            ("Acrylic base", FluentMaterialRecipe.acrylicBase(theme.brightness)),
            ("Accent acrylic", FluentMaterialRecipe.accentAcrylic(theme.brightness, accent: theme.accentColor)),
            ("Mica", FluentMaterialRecipe.mica(theme.brightness)),
            ("Mica Alt", FluentMaterialRecipe.micaAlt(theme.brightness)),
        ]
        return SamplePage(
            "Materials",
            "Acrylic is a blur of what is behind a transient surface with the tint's lightness blended on; Mica is opaque and leans toward the wallpaper, sampled once; Smoke dims what a modal covers. The recipes are WinUI's own brush resources.",
            samples: [
                Sample("Acrylic and Mica over a busy backdrop", child: SizedBox(height: 180, child: Stack {
                    Positioned(fill: (), child: backdrop)
                    Positioned(left: 16, top: 20, width: 190, height: 110, child: Acrylic(
                        child: label("Acrylic default"), borderRadius: FluentCorners.overlayRadius))
                    Positioned(left: 222, top: 20, width: 190, height: 110, child: Acrylic(
                        child: label("Acrylic base"),
                        recipe: FluentMaterialRecipe.acrylicBase(theme.brightness),
                        borderRadius: FluentCorners.overlayRadius))
                    Positioned(left: 428, top: 20, width: 150, height: 110, child: ClipRRect(
                        borderRadius: FluentCorners.overlayRadius,
                        child: Mica(child: label("Mica"))))
                    Positioned(left: 594, top: 20, width: 150, height: 110, child: ClipRRect(
                        borderRadius: FluentCorners.overlayRadius,
                        child: Mica(child: label("Mica Alt"), kind: .alt)))
                    Positioned(left: 0, right: 0, bottom: 0, height: 36, child: Smoke {
                        Center(child: Text("Smoke", style: t.bodyStrong?.copyWith(color: Color(0xFFFFFFFF))))
                    })
                })),
                Sample("Recipes", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    Row(spacing: FluentSpacing.m) {
                        SizedBox(width: 140, child: Text("Material", style: t.caption))
                        SizedBox(width: 60, child: Text("Tint", style: t.caption))
                        SizedBox(width: 90, child: Text("Tint opacity", style: t.caption))
                        SizedBox(width: 110, child: Text("Luminosity", style: t.caption))
                        SizedBox(width: 60, child: Text("Fallback", style: t.caption))
                        Text("Blur", style: t.caption)
                    }
                    for (name, rcp) in recipes {
                        Row(spacing: FluentSpacing.m) {
                            SizedBox(width: 140, child: Text(name, style: t.body))
                            SizedBox(width: 60, child: _chip(rcp.tintColor, context))
                            SizedBox(width: 90, child: Text("\(rcp.tintOpacity)", style: t.body))
                            SizedBox(width: 110, child: Text("\(rcp.luminosityOpacity)", style: t.body))
                            SizedBox(width: 60, child: _chip(rcp.fallbackColor, context))
                            Text(rcp.blurAmount > 0 ? "\(Int(rcp.blurAmount))" : "—", style: t.body)
                        }
                    }
                }),
                Sample("Mica from one wallpaper sample", child: Row(spacing: FluentSpacing.m) {
                    for (name, sample) in wallpapers {
                        Column(spacing: FluentSpacing.xs) {
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    color: Mica.color(kind: .base, brightness: theme.brightness, sample: sample),
                                    border: Border.all(color: theme.resources.controlStrokeColorDefault, width: 1),
                                    borderRadius: FluentCorners.overlayRadius),
                                child: SizedBox(width: 96, height: 64))
                            Text(name, style: t.caption)
                        }
                    }
                }),
            ])
    }

    private func _chip(_ color: Color, _ context: any BuildContext) -> Widget {
        DecoratedBox(
            decoration: BoxDecoration(
                color: color,
                border: Border.all(color: FluentTheme.of(context).resources.controlStrokeColorDefault, width: 1),
                borderRadius: FluentCorners.controlRadius),
            child: SizedBox(width: 24, height: 24))
    }
}

// MARK: - Elevation

final class ElevationPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let t = theme.typography
        let levels: [(String, Double, Double)] = [
            ("layer 1", FluentElevation.layer, FluentCorners.control),
            ("control 2", FluentElevation.control, FluentCorners.control),
            ("card 8", FluentElevation.card, FluentCorners.control),
            ("tooltip 16", FluentElevation.tooltip, FluentCorners.tooltip),
            ("flyout 32", FluentElevation.flyout, FluentCorners.overlay),
            ("dialog 128", FluentElevation.dialog, FluentCorners.overlay),
        ]
        return SamplePage(
            "Elevation",
            "Depth as shadow, plus a 1px stroke on every raised surface. Windows pairs each role with a value — a control sits at 2, a card at 8, a tooltip at 16, a flyout at 32, a dialog or window at 128 — and the shadow is Fluent 2's two-layer recipe for that value: an ambient halo and a key shadow offset by half the elevation.",
            samples: [
                Sample("The ramp", child: Padding(padding: EdgeInsets(left: 0, top: 8, right: 0, bottom: 40)) {
                    Row(spacing: FluentSpacing.xxl) {
                        for (name, level, radius) in levels {
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    color: theme.menuColor,
                                    border: Border.all(color: theme.resources.surfaceStrokeColorFlyout,
                                                       width: FluentStrokeWidth.thin),
                                    borderRadius: BorderRadius.circular(radius),
                                    boxShadow: FluentElevation.shadows(level, brightness: theme.brightness)),
                                child: SizedBox(width: 112, height: 72, child: Center(child: Text(name, style: t.caption))))
                        }
                    }
                }),
                Sample("Layering: base, then content on LayerFillColorDefault", child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: theme.resources.solidBackgroundFillColorBase,
                        borderRadius: FluentCorners.overlayRadius),
                    child: Padding(padding: EdgeInsets(all: FluentSpacing.l)) {
                        Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                            Text("Base layer — navigation and commands live here", style: t.body)
                            DecoratedBox(
                                decoration: BoxDecoration(
                                    color: theme.resources.layerFillColorDefault,
                                    border: Border.all(color: theme.resources.cardStrokeColorDefault, width: 1),
                                    borderRadius: FluentCorners.overlayRadius),
                                child: Padding(padding: EdgeInsets(all: FluentSpacing.l)) {
                                    Text("Content layer — the app's central experience, contiguous or as cards", style: t.body)
                                })
                        }
                    })),
            ])
    }
}

// MARK: - Motion

final class MotionPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let t = theme.typography
        let windows: [(String, FluentMotion.Spec, String)] = [
            ("Direct entrance", FluentMotion.directEntrance, "decelerate mid · position, scale, rotation"),
            ("Point to point", FluentMotion.pointToPoint, "cubic(0.55, 0.55, 0, 1) · existing elements"),
            ("Direct exit", FluentMotion.directExit, "decelerate mid · always with a fade"),
            ("Gentle exit", FluentMotion.gentleExit, "accelerate mid · position, scale"),
            ("Fade", FluentMotion.fade, "linear · opacity only"),
        ]
        let curves: [(String, any Curve)] = [
            ("accelerateMax", FluentMotion.accelerateMax), ("accelerateMid", FluentMotion.accelerateMid),
            ("accelerateMin", FluentMotion.accelerateMin), ("decelerateMax", FluentMotion.decelerateMax),
            ("decelerateMid", FluentMotion.decelerateMid), ("decelerateMin", FluentMotion.decelerateMin),
            ("easyEaseMax", FluentMotion.easyEaseMax), ("easyEase", FluentMotion.easyEase),
        ]
        let durations: [(String, Duration)] = [
            ("ultraFast", FluentMotion.ultraFast), ("faster", FluentMotion.faster), ("fast", FluentMotion.fast),
            ("normal", FluentMotion.normal), ("gentle", FluentMotion.gentle), ("slow", FluentMotion.slow),
            ("slower", FluentMotion.slower), ("ultraSlow", FluentMotion.ultraSlow),
        ]
        return SamplePage(
            "Motion",
            "Windows' motion is fast, direct and context-appropriate. Things arriving decelerate; things leaving accelerate and always fade; the same surface always enters and leaves the same way. The Fluent 2 ramp below is the vocabulary, the Windows table is which words a surface uses.",
            samples: [
                Sample("Windows 11's table", child: Column(crossAxisAlignment: .start, spacing: FluentSpacing.s) {
                    for (name, spec, note) in windows {
                        Row(spacing: FluentSpacing.m) {
                            SizedBox(width: 150, child: Text(name, style: t.body))
                            SizedBox(width: 70, child: Text("\(milliseconds(spec.duration)) ms", style: t.bodyStrong))
                            _curveStrip(spec.curve, theme)
                            Text(note, style: t.caption)
                        }
                    }
                }),
                Sample("Fluent 2 curves, sampled at t = 0.1 … 1.0", child: Wrap(spacing: FluentSpacing.xxl, runSpacing: FluentSpacing.m) {
                    for (name, curve) in curves {
                        Column(crossAxisAlignment: .start, spacing: FluentSpacing.xs) {
                            _curveStrip(curve, theme)
                            Text(name, style: t.caption)
                        }
                    }
                }),
                Sample("Fluent 2 durations", child: Row(spacing: FluentSpacing.l) {
                    for (name, d) in durations {
                        Column(spacing: FluentSpacing.xs) {
                            Text("\(milliseconds(d))", style: t.bodyStrong)
                            Text(name, style: t.caption)
                        }
                    }
                }),
            ])
    }

    /// Ten bars whose heights are the curve's value at t = 0.1 … 1.0.
    private func _curveStrip(_ curve: any Curve, _ theme: FluentThemeData) -> Widget {
        let ink = theme.accentColor.defaultBrushFor(theme.brightness)
        return Row(crossAxisAlignment: .end, spacing: 2) {
            for i in 1...10 {
                let v = curve.transform(Double(i) / 10.0)
                DecoratedBox(
                    decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(1)),
                    child: SizedBox(width: 6, height: max(2, 24 * v)))
            }
        }
    }
}

// MARK: - Iconography

final class IconographyPage: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        let theme = FluentTheme.of(context)
        let t = theme.typography
        let icons: [(String, IconData)] = [
            ("home", FluentSystemIcons.home), ("search", FluentSystemIcons.search), ("settings", FluentSystemIcons.settings),
            ("back", FluentSystemIcons.back), ("forward", FluentSystemIcons.forward), ("up", FluentSystemIcons.up),
            ("refresh", FluentSystemIcons.refresh), ("add", FluentSystemIcons.add), ("close", FluentSystemIcons.close),
            ("check", FluentSystemIcons.check), ("edit", FluentSystemIcons.edit), ("delete", FluentSystemIcons.delete),
            ("copy", FluentSystemIcons.copy), ("cut", FluentSystemIcons.cut), ("paste", FluentSystemIcons.paste),
            ("rename", FluentSystemIcons.rename), ("share", FluentSystemIcons.share), ("sort", FluentSystemIcons.sort),
            ("more", FluentSystemIcons.more), ("info", FluentSystemIcons.info), ("link", FluentSystemIcons.link),
            ("print", FluentSystemIcons.print), ("history", FluentSystemIcons.history), ("favorite", FluentSystemIcons.favorite),
            ("pin", FluentSystemIcons.pin), ("grid", FluentSystemIcons.grid), ("window", FluentSystemIcons.window),
            ("folder", FluentSystemIcons.folder), ("folderOpen", FluentSystemIcons.folderOpen), ("document", FluentSystemIcons.document),
            ("pictures", FluentSystemIcons.pictures), ("music", FluentSystemIcons.music), ("video", FluentSystemIcons.video),
            ("download", FluentSystemIcons.download), ("cloud", FluentSystemIcons.cloud), ("drive", FluentSystemIcons.drive),
            ("wifiFull", FluentSystemIcons.wifiFull), ("ethernet", FluentSystemIcons.ethernet), ("bluetooth", FluentSystemIcons.bluetooth),
            ("airplane", FluentSystemIcons.airplane), ("volume", FluentSystemIcons.volume), ("mute", FluentSystemIcons.mute),
            ("brightness", FluentSystemIcons.brightness), ("battery", FluentSystemIcons.battery), ("batteryCharging", FluentSystemIcons.batteryCharging),
            ("clock", FluentSystemIcons.clock), ("bell", FluentSystemIcons.bell), ("calendar", FluentSystemIcons.calendar),
            ("person", FluentSystemIcons.person), ("power", FluentSystemIcons.power), ("lock", FluentSystemIcons.lock),
            ("moon", FluentSystemIcons.moon), ("sun", FluentSystemIcons.sun), ("keyboard", FluentSystemIcons.keyboard),
            ("laptop", FluentSystemIcons.laptop), ("desktop", FluentSystemIcons.desktop), ("apps", FluentSystemIcons.apps),
        ]
        return SamplePage(
            "Iconography",
            "Fluent System Icons, Microsoft's open icon set: monoline glyphs drawn for 16, 20 and 24px. The system font for Windows' own chrome is Segoe Fluent Icons; these are its published twin.",
            samples: [
                Sample("Sizes", child: Row(crossAxisAlignment: .end, spacing: FluentSpacing.xl) {
                    for size in [16.0, 20.0, 24.0, 32.0, 48.0] {
                        Column(spacing: FluentSpacing.xs) {
                            Icon(FluentSystemIcons.settings, size: size)
                            Text("\(Int(size))", style: t.caption)
                        }
                    }
                }),
                Sample("The set", child: Wrap(spacing: FluentSpacing.s, runSpacing: FluentSpacing.s) {
                    for (name, icon) in icons {
                        SizedBox(width: 104, height: 72, child: Column(mainAxisAlignment: .center, spacing: FluentSpacing.xs) {
                            Icon(icon, size: 24)
                            Text(name, style: t.caption, overflow: .ellipsis, maxLines: 1)
                        })
                    }
                }),
            ])
    }
}
#endif
