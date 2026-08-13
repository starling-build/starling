// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// Where an iOS terminal says which machine it is a terminal for.
//
// The desktop never needed this: it inherits a shell, an environment and a
// working directory from whatever launched it. An app on a phone inherits
// nothing — there is no argv a person can reach and no environment to read —
// so the destination has to be asked for, and remembered.

#if os(iOS)
import Flutter
import FlutterSwiftBridge
import Foundation

/// Everything needed to open a session, and the part of it worth keeping.
struct SSHTarget {
    var host: String
    var port: Int
    var user: String
    var password: String


    /// Host, port and user are remembered; the password is not.
    ///
    /// Not because UserDefaults is the wrong drawer for it — it is, but the
    /// keychain is right there — but because this app has no lock of its own,
    /// so a stored password is one that anyone holding the unlocked phone can
    /// use. Typing it per connection is the honest default until there is a
    /// biometric gate in front of it.
    static func remembered() -> SSHTarget {
        SSHTarget(host: UserDefaults.standard.string(forKey: "starling.ssh.host") ?? "",
                  port: UserDefaults.standard.object(forKey: "starling.ssh.port") as? Int ?? 22,
                  user: UserDefaults.standard.string(forKey: "starling.ssh.user") ?? "",
                  password: "")
    }

    func remember() {
        UserDefaults.standard.set(host, forKey: "starling.ssh.host")
        UserDefaults.standard.set(port, forKey: "starling.ssh.port")
        UserDefaults.standard.set(user, forKey: "starling.ssh.user")
    }
}

class SSHConnectView: StatefulWidget {
    let onConnect: (SSHTarget) -> Void

    init(onConnect: @escaping (SSHTarget) -> Void) {
        self.onConnect = onConnect
        super.init()
    }

    override func createState() -> State<StatefulWidget> {
        return _SSHConnectViewState()
    }
}

private class _SSHConnectViewState: State<StatefulWidget>, @unchecked Sendable {
    private var target = SSHTarget.remembered()

    private var canConnect: Bool {
        !target.host.isEmpty && !target.user.isEmpty && !target.password.isEmpty
    }

    private func field(_ label: String, _ value: String,
                       placeholder: String,
                       obscure: Bool = false,
                       _ set: @escaping (String) -> Void) -> Widget {
        return Padding(padding: EdgeInsets(bottom: 14)) {
            Column(crossAxisAlignment: .start) {
                Padding(padding: EdgeInsets(bottom: 4)) {
                    Text(label, style: TextStyle(
                        color: Color(0xFF98989D), fontSize: 12))
                }
                MacosTextField(
                    controller: TextEditingController(text: value),
                    placeholder: placeholder,
                    onChanged: { [weak self] text in
                        // No setState: the fields own their own text through
                        // their controllers, and rebuilding here would rebuild
                        // them from `value` mid-keystroke. Only `canConnect`
                        // depends on this, and the button reads it on the
                        // rebuild the submit triggers.
                        set(text)
                        self?.setState {}
                    },
                    obscureText: obscure)
            }
        }
    }

    override func build(_ context: any BuildContext) -> Widget {
        return ColoredBox(color: Color(0xFF1C1C1E)) {
            Center {
                Padding(padding: EdgeInsets(all: 24)) {
                    Column(mainAxisSize: .min, crossAxisAlignment: .stretch) {
                        Padding(padding: EdgeInsets(bottom: 24)) {
                            Text("Connect", style: TextStyle(
                                color: Color(0xFFFFFFFF), fontSize: 28,
                                fontWeight: .w600))
                        }
                        field("HOST", target.host, placeholder: "mac-mini.local") {
                            self.target.host = $0
                        }
                        field("USER", target.user, placeholder: "your account") {
                            self.target.user = $0
                        }
                        field("PASSWORD", target.password, placeholder: "",
                              obscure: true) {
                            self.target.password = $0
                        }
                        field("PORT", String(target.port), placeholder: "22") {
                            self.target.port = Int($0) ?? 22
                        }
                        Padding(padding: EdgeInsets(top: 10)) {
                            PushButton(
                                child: Text(canConnect ? "Connect"
                                                       : "Host, user and password"),
                                controlSize: .large,
                                onPressed: canConnect
                                    ? { (self.widget as! SSHConnectView).onConnect(self.target) }
                                    : nil)
                        }
                    }
                }
            }
        }
    }
}
#endif
