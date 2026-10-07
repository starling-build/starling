// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#if os(WASI)
import Flutter
import FlutterSwiftBridge
import FlutterWeb
import Foundation

private nonisolated(unsafe) var navigateLanding: ((Int) -> Void)?
private nonisolated(unsafe) var resizeLanding: ((Bool) -> Void)?

/// Small embed control surface; the deck and rendering stay inside Slides.
@_expose(wasm, "office_landing_go")
@_cdecl("office_landing_go")
func officeLandingGo(_ index: Int32) { navigateLanding?(Int(index)) }

@_expose(wasm, "office_landing_portrait")
@_cdecl("office_landing_portrait")
func officeLandingPortrait(_ portrait: Int32) { resizeLanding?(portrait != 0) }

final class OfficeLandingView: StatefulWidget {
    override func createState() -> State<StatefulWidget> { _OfficeLandingState() }
}

private final class _OfficeLandingState: State<StatefulWidget> {
    private var wide: DeckController!
    private var tall: DeckController!
    private let images = SlideTextCache()
    private var showKey = GlobalKey<State<StatefulWidget>>()
    private var portrait = false
    private var index = 0

    override func initState() {
        super.initState()
        OfficeFonts.register()
        portrait = WebPlatform.defaultRouteName.hasSuffix("/portrait")
        func read(_ name: String) -> DeckController {
            guard let bytes = WebFiles.startupFiles.removeValue(forKey: name),
                  let (state, theme, package) = try? Pptx.read(bytes), !state.slides.isEmpty else {
                fatalError("Missing or invalid landing presentation: \(name)")
            }
            let deck = DeckController()
            deck.load(state, theme: theme, package: package)
            return deck
        }
        wide = read("landing-wide.pptx")
        tall = read("landing-tall.pptx")
        resizeLanding = { [weak self] next in
            guard let self, self.portrait != next else { return }
            self.setState {
                self.portrait = next
                self.showKey = GlobalKey<State<StatefulWidget>>()
            }
        }
        navigateLanding = { [weak self] i in
            (self?.showKey.currentState as? SlideShowState)?.showSlide(i)
        }
        hostDebugQuery = { [weak self] kind in
            guard kind == "landing", let self else { return nil }
            return "{\"index\":\(self.index),\"count\":\(self.wide.slides.count),\"portrait\":\(self.portrait == true)}"
        }
    }

    override func dispose() {
        navigateLanding = nil
        resizeLanding = nil
        hostDebugQuery = nil
        super.dispose()
    }

    override func build(_ context: any BuildContext) -> Widget {
        SlideShowView(deck: portrait ? tall : wide, images: images,
                      start: index, onEnd: {}, key: showKey, landing: true,
                      onSlideChanged: { [weak self] index in self?.index = index })
    }
}
#endif
