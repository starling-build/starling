// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

// Ending the session, from the shell's power button.
//
// Separate from `Win32Control` on purpose. Everything there is reversible with
// the same click that caused it — mute, dark mode, the Wi-Fi radio. Nothing
// here is: these take the user's session away, and a type that mixes the two
// makes it possible to reach one by autocomplete while looking for the other.

#if os(Windows)
import FlutterWin32Bridge

public enum Win32Session {

    /// What a power button can do, in the order a menu should offer them —
    /// least destructive first, so the pointer travels furthest to reach the
    /// one that discards the most.
    public enum Action: Int32, CaseIterable, Sendable {
        case lock = 0
        case signOut = 1
        case sleep = 2
        case restart = 3
        case shutDown = 4

        public var label: String {
            switch self {
            case .lock: return "Lock"
            case .signOut: return "Sign out"
            case .sleep: return "Sleep"
            case .restart: return "Restart"
            case .shutDown: return "Shut down"
            }
        }

        /// Whether it needs the shutdown privilege, which a restricted
        /// account may not have.
        public var needsPowerPrivilege: Bool {
            self == .restart || self == .shutDown
        }
    }

    /// Whether this account may restart or power off. Asking also ENABLES the
    /// privilege, which is why the shell asks once at startup rather than at
    /// the moment of the click: a process holds SE_SHUTDOWN_NAME disabled by
    /// default, and `ExitWindowsEx` answers ERROR_ACCESS_DENIED rather than
    /// anything that sounds like a missing privilege.
    public static var canPowerOff: Bool { flwin32_session_can_power_off() != 0 }

    /// Performs the action. Returns false if Windows refused; on success the
    /// session is already on its way out, so there is nothing to come back to.
    @discardableResult
    public static func perform(_ action: Action) -> Bool {
        flwin32_session_action(action.rawValue) != 0
    }
}
#endif
