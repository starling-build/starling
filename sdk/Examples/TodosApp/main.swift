// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Todos — the todo-list app every UI toolkit demos (TodoMVC, and Flutter's
// own todo codelabs), here as a FlutterSwift port built on the framework's
// MacosUI widget set: toolbar + text field entry, checkbox completion with
// strikethrough, per-item delete, an items-left count, and clearing of
// completed items.
//
//   swift run -c release TodosApp

#if os(Linux) || os(WASI)
import CupertinoIcons
import ExampleHost
import Flutter
import FlutterSwiftBridge

struct Todo {
    let id: Int
    var title: String
    var done: Bool
}

class TodoHomePage: StatefulWidget {
    override func createState() -> State<StatefulWidget> {
        return _TodoHomePageState()
    }
}

class _TodoHomePageState: State<StatefulWidget> {
    // Seeded with TodoMVC's traditional starter items so the list isn't
    // empty on first launch.
    private var _todos: [Todo] = [
        Todo(id: 0, title: "Taste Swift", done: true),
        Todo(id: 1, title: "Port a Flutter app", done: false),
        Todo(id: 2, title: "Ship it", done: false),
    ]
    private var _nextId = 3
    private let _controller = TextEditingController()

    override func initState() {
        super.initState()
        // MacosIcon draws from the CupertinoIcons font; the engine is live by
        // the time the tree first mounts.
        CupertinoIcons.registerFont()
    }

    private func _addTodo(_ title: String) {
        let trimmed = title.trimmingWhitespace(newlines: false)
        guard !trimmed.isEmpty else { return }
        setState {
            _todos.append(Todo(id: _nextId, title: trimmed, done: false))
            _nextId += 1
        }
        _controller.clear()
        print("[Todos] added: \(trimmed)")
    }

    private func _toggle(_ id: Int, _ done: Bool) {
        setState {
            if let i = _todos.firstIndex(where: { $0.id == id }) {
                _todos[i].done = done
            }
        }
    }

    private func _remove(_ id: Int) {
        setState {
            _todos.removeAll { $0.id == id }
        }
        print("[Todos] removed item \(id)")
    }

    private func _clearCompleted() {
        setState {
            _todos.removeAll { $0.done }
        }
        print("[Todos] cleared completed")
    }

    private func _buildRow(_ todo: Todo, theme: MacosThemeData) -> Widget {
        let titleStyle: Flutter.TextStyle = todo.done
            ? TextStyle(
                color: Color(0x61000000),
                fontSize: 13,
                decoration: .lineThrough
            )
            : TextStyle(color: Color(0xDD000000), fontSize: 13)
        return MacosListTile(
            leading: MacosCheckbox(
                value: todo.done,
                onChanged: { [weak self] checked in
                    self?._toggle(todo.id, checked)
                }
            ),
            title: Text(todo.title, style: titleStyle, maxLines: 1),
            trailing: MacosIconButton(
                icon: MacosIcon(
                    icon: CupertinoIcons.delete,
                    color: Color(0x8A000000),
                    size: 15
                ),
                onPressed: { [weak self] in self?._remove(todo.id) }
            )
        )
    }

    override func build(_ context: any BuildContext) -> Widget {
        let theme = MacosTheme.of(context)
        let remaining = _todos.filter { !$0.done }.count
        let hasCompleted = _todos.contains { $0.done }

        let content = Padding(
            padding: EdgeInsets(left: 20, top: 16, right: 20, bottom: 16),
            child: Column(crossAxisAlignment: .stretch, children: [
                Row(children: [
                    Expanded(
                        child: MacosTextField(
                            controller: _controller,
                            placeholder: "What needs to be done?",
                            onSubmitted: { [weak self] text in self?._addTodo(text) }
                        )
                    ),
                    SizedBox(width: 8, height: 1),
                    PushButton(
                        child: Text("Add"),
                        onPressed: { [weak self] in
                            guard let self = self else { return }
                            self._addTodo(self._controller.text)
                        }
                    ),
                ]),
                SizedBox(width: 1, height: 12),
                Expanded(
                    child: ListView(
                        children: _todos.map { _buildRow($0, theme: theme) }
                    )
                ),
                SizedBox(
                    height: 1,
                    child: DecoratedBox(
                        decoration: BoxDecoration(color: theme.dividerColor)
                    )
                ),
                Padding(
                    padding: EdgeInsets(vertical: 10),
                    child: Row(children: [
                        Text(
                            "\(remaining) item\(remaining == 1 ? "" : "s") left",
                            style: TextStyle(color: Color(0x8A000000), fontSize: 12)
                        ),
                        Expanded(child: SizedBox(width: 1, height: 1)),
                        PushButton(
                            child: Text("Clear completed"),
                            onPressed: hasCompleted
                                ? { [weak self] in self?._clearCompleted() }
                                : nil,
                            secondary: true
                        ),
                    ])
                ),
            ])
        )

        return MacosScaffold(
            children: [content],
            toolBar: MacosToolBar(title: Text("todos"))
        )
    }
}

runExampleApp(title: "Todos", width: 520, height: 700) {
    MacosApp(
        theme: MacosThemeData(brightness: .light),
        home: TodoHomePage(),
        title: "todos"
    )
}

#else
fatalError("The example apps currently target Linux desktop sessions.")
#endif
