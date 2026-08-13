// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// The classic Flutter counter — the app `flutter create` generates, and the
// first Flutter app almost everyone runs — ported from Dart to FlutterSwift.
// Same structure as the original: MyApp wrapping a stateful MyHomePage whose
// State owns _counter, with a FloatingActionButton driving setState.
//
//   swift run -c release CounterApp

#if os(Linux) || os(Windows) || os(macOS)
import CupertinoIcons
import ExampleHost
import Flutter
import FlutterSwiftBridge

// class MyApp extends StatelessWidget — the MaterialApp shell.
class MyApp: StatelessWidget {
    override func build(_ context: any BuildContext) -> Widget {
        return Directionality(
            textDirection: .ltr,
            child: MyHomePage(title: "Flutter Demo Home Page")
        )
    }
}

// class MyHomePage extends StatefulWidget
class MyHomePage: StatefulWidget {
    let title: String

    init(title: String) {
        self.title = title
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _MyHomePageState()
    }
}

// class _MyHomePageState extends State<MyHomePage>
class _MyHomePageState: State<StatefulWidget> {
    private var _counter = 0

    private func _incrementCounter() {
        setState {
            _counter += 1
        }
        print("[CounterApp] counter = \(_counter)")
    }

    override func build(_ context: any BuildContext) -> Widget {
        let homePage = widget as! MyHomePage
        return MaterialScaffold(
            appBar: MaterialAppBar(title: homePage.title),
            body: Center(
                child: Column(
                    mainAxisAlignment: .center,
                    children: [
                        Text(
                            "You have pushed the button this many times:",
                            style: TextStyle(color: MaterialColors.body, fontSize: 14)
                        ),
                        Text(
                            "\(_counter)",
                            // The original renders the count in
                            // textTheme.headline4: 34px, black54.
                            style: TextStyle(color: MaterialColors.headline, fontSize: 34)
                        ),
                    ]
                )
            ),
            floatingActionButton: MaterialFloatingActionButton(
                onPressed: { [weak self] in self?._incrementCounter() },
                child: Icon(CupertinoIcons.add, color: MaterialColors.onPrimary)
            )
        )
    }
}

runExampleApp(title: "Flutter Demo", width: 480, height: 720) { MyApp() }

#else
fatalError("The example apps currently target Linux, Windows and macOS desktop sessions.")
#endif
