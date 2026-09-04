// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One app, as the desktop knows it.
///
/// Assembled from two key files: the shipped catalog record (static product
/// facts — name, colour, how to install it, how to launch it) and, when the
/// App Store installed it, the record `app-install` wrote at install time
/// (host facts that are only knowable once it is on disk — where its
/// `.desktop` entry landed, what window class it reports, where its icon is).
///
/// Everything the launcher, the dock and the store display comes from here.
/// Adding an app means adding one file to `catalog.d/`, not editing a table in
/// four Swift files and two shell scripts.
public struct AppRecord: Sendable {

    /// Opening geometry for a first-party app's window, in logical pixels.
    public struct WindowGeometry: Sendable {
        public let x: Double, y: Double, width: Double, height: Double
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    /// How the app is installed and launched. The shell switches on this
    /// instead of on app ids.
    public enum Kind: String, Sendable {
        /// A Starling app, shipped with the desktop; `exec` is its executable
        /// name in FLUTTER_APPS_DIR.
        case firstParty = "first-party"
        /// A Linux app on the host; `exec` names its `app-run` recipe.
        case host
        /// An Android app inside Waydroid; `exec` names its `android-app` arg.
        case android
        /// An X11-only app in its own rootful Xwayland (WeChat); `exec` names
        /// the launcher script.
        case x11
        /// A virtual machine's console; `domain` names the libvirt domain and
        /// there is no process to launch — the shell opens the guest's display
        /// in-process. See docs/plans/guest-display.md.
        case vm
        /// An app INSIDE a virtual machine, shown as a window of its own
        /// (docs/plans/guest-seamless.md): `domain` names the VM and `exec`
        /// is what the guest's helper launches — an AppsFolder id, which is
        /// the AppUserModelID for a packaged app. Records of this kind are
        /// not shipped; the shell writes them from the guest's own catalog
        /// into `AppRegistry.guestAppsDir`, one per app, and they are
        /// installed by definition.
        case guestApp = "guest-app"
    }

    // ── Catalog: shipped, static ─────────────────────────────────────────
    public let id: String
    public let name: String
    public let kind: Kind
    /// Launcher (Launchpad) sort key; ties break on name.
    public let order: Int
    /// Painter glyph drawn when no host icon resolves. Starling ships no
    /// third-party artwork, so this is a neutral shape, never a brand mark.
    public let glyph: String
    /// Tile base colour, 0xRRGGBB.
    public let color: UInt32
    /// Position in the default dock; nil means launcher-only until pinned.
    public let dockOrder: Int?

    // Store copy.
    public let category: String
    public let publisher: String
    public let subtitle: String
    public let sizeLabel: String
    public let details: String

    /// `app-run` recipe / executable name / `android-app` arg, per `kind`.
    public let exec: String
    /// Where a first-party app's window opens (`Window=x,y,w,h`). Third-party
    /// clients size their own windows, so this is nil for them.
    public let windowRect: WindowGeometry?
    /// `app-install` recipe name. Nil means the store cannot install it —
    /// first-party apps ship with the desktop, WeChat is a host install.
    public let installRecipe: String?
    /// Paths whose existence means "installed", for apps installed outside
    /// the store (`apt install gimp` by hand still lights up the launcher).
    public let bins: [String]
    /// `.desktop` basenames to try when resolving the icon and window class.
    public let desktopEntries: [String]
    /// Window class fallbacks, for apps that ship no `.desktop` entry to read
    /// `StartupWMClass` from (IntelliJ's tarball is one).
    public let wmClasses: [String]
    /// Window-title substrings, for the few windows that carry no usable
    /// app_id at all: WeChat inside rootful Xwayland, and Waydroid, which
    /// renders every Android app into one window whose title follows the
    /// foreground app.
    public let titleMatches: [String]
    /// Show `name` instead of the window's own title. For the one case where
    /// the title is an implementation detail: WeChat's window is the whole
    /// rootful Xwayland screen, titled `Xwayland on :1`.
    public let renameWindows: Bool
    /// `Gpu=discrete`: render on the discrete GPU when the machine has one
    /// (PRIME offload — docs/plans/prime.md). The launch paths translate this
    /// per spawn (first-party: STARLING_APP_DRM_DEVICE; host: the standard
    /// DRI_PRIME/__NV_PRIME_RENDER_OFFLOAD envs via app-run). On a single-GPU
    /// machine it is a no-op.
    public let discreteGpu: Bool
    /// `Agent=1`: this app drives a computer-use agent, so a new workspace can
    /// offer to run it. What it means concretely is that the app spawns a
    /// broker client — Claude Desktop starts the `starling-computer-use` MCP
    /// server as a child — and the shell pairs the two by process ancestry, so
    /// the windows that agent opens land in the workspace beside it.
    ///
    /// A flag rather than a list in the shell, for the usual reason: the
    /// second such app must be one file here and nothing else.
    public let agentApp: Bool
    /// Sealed-image install (Starling OS): the official .deb and the path
    /// inside it that proves the extraction worked.
    public let debURL: String?
    public let debMarker: String?

    // ── Installed: written by app-install, absent until then ─────────────
    /// The `.desktop` file found on this host at install time.
    public let desktopFile: String?
    /// Raster icon resolved on this host. Never shipped by us — third-party
    /// marks belong to their owners — so this is always a path into the
    /// user's own install.
    public let iconPath: String?
    public let version: String?
    public let installedAt: Int?
    /// True when `app-install` recorded this app, or a `bins` path exists, or
    /// (first-party) the executable is present.
    public let installed: Bool

    /// Every string a window's `xdg_toplevel.set_app_id` might carry for this
    /// app: what the host's `.desktop` declared, plus the catalog fallbacks.
    public let appIds: [String]

    /// URL schemes this app handles (`UrlSchemes=slack` — no `://`). The
    /// xdg-open shim resolves handoffs through these instead of a scheme
    /// table of its own: the record is the ONE description of the app, and a
    /// scheme living anywhere else is how tables drift. `http;https` marks a
    /// browser; the Default Apps pane offers exactly the installed records
    /// that declare them.
    public let urlSchemes: [String]

    /// For `Kind=vm`: the libvirt domain whose console this record opens.
    /// `STARLING_GUEST_DOMAIN` overrides it, for a dev box whose domain is
    /// not the one the release ships against. For `Kind=guest-app`: the
    /// domain the app lives in.
    public let domain: String?

    public init(
        id: String, name: String, kind: Kind, order: Int, glyph: String,
        color: UInt32, dockOrder: Int?, category: String, publisher: String,
        subtitle: String, sizeLabel: String, details: String, exec: String,
        windowRect: WindowGeometry?,
        installRecipe: String?, bins: [String], desktopEntries: [String],
        wmClasses: [String], titleMatches: [String], renameWindows: Bool,
        discreteGpu: Bool = false,
        agentApp: Bool = false,
        debURL: String?,
        debMarker: String?, desktopFile: String?, iconPath: String?,
        version: String?, installedAt: Int?, installed: Bool, appIds: [String],
        urlSchemes: [String] = [],
        domain: String? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.order = order
        self.glyph = glyph
        self.color = color
        self.dockOrder = dockOrder
        self.category = category
        self.publisher = publisher
        self.subtitle = subtitle
        self.sizeLabel = sizeLabel
        self.details = details
        self.exec = exec
        self.domain = domain
        self.windowRect = windowRect
        self.installRecipe = installRecipe
        self.bins = bins
        self.desktopEntries = desktopEntries
        self.wmClasses = wmClasses
        self.titleMatches = titleMatches
        self.renameWindows = renameWindows
        self.agentApp = agentApp
        self.discreteGpu = discreteGpu
        self.debURL = debURL
        self.debMarker = debMarker
        self.desktopFile = desktopFile
        self.iconPath = iconPath
        self.version = version
        self.installedAt = installedAt
        self.installed = installed
        self.appIds = appIds
        self.urlSchemes = urlSchemes
    }

    /// True when a window reporting `appId` belongs to this app. Wayland's
    /// app_id and the host `.desktop` id are the same namespace, so a match is
    /// either exact or exact-minus-the-`.desktop` suffix; the compare is
    /// case-insensitive because clients are inconsistent about it (Chrome
    /// reports `google-chrome`, VS Code `Code`).
    public func matches(appId: String) -> Bool {
        let want = Self.idForms(appId)
        guard !want.isEmpty else { return false }
        return appIds.contains { !Self.idForms($0).isDisjoint(with: want) }
    }

    /// True when a window titled `title` belongs to this app — only for the
    /// apps whose catalog record declares `TitleMatch`, because they arrive
    /// with no usable app_id. Never a general fallback: matching IntelliJ by
    /// title fails the moment a project opens and the title becomes
    /// `untitled – Main.java`.
    public func matches(title: String) -> Bool {
        guard !titleMatches.isEmpty else { return false }
        return titleMatches.contains { title.contains($0) }
    }

    /// The forms an app_id may legitimately take: as written, and — when it
    /// ends in `.desktop` — without that suffix.
    ///
    /// Both are kept rather than normalizing to one, because an app_id can
    /// legitimately END in ".desktop": Telegram's is literally
    /// `org.telegram.desktop`, and unconditionally stripping the suffix throws
    /// away the component that names the app. Comparing sets means the
    /// tolerance is added, never subtracted.
    static func idForms(_ s: String) -> Set<String> {
        let lower = s.lowercased()
        guard !lower.isEmpty else { return [] }
        var forms: Set<String> = [lower]
        if lower.hasSuffix(".desktop") {
            let stripped = String(lower.dropLast(".desktop".count))
            if !stripped.isEmpty { forms.insert(stripped) }
        }
        return forms
    }
}
