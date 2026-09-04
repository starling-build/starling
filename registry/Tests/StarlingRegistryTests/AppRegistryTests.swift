// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import StarlingRegistry

/// The registry itself: loading a catalog, merging what app-install recorded,
/// and deciding what counts as installed.
final class AppRegistryTests: XCTestCase {

    private var catalogDir = ""
    private var recordsDir = ""
    private var guestDir = ""

    override func setUp() {
        super.setUp()
        let base = NSTemporaryDirectory() + "starling-registry-tests-\(getpid())"
        catalogDir = base + "/catalog.d"
        recordsDir = base + "/installed.d"
        guestDir = base + "/guest-apps.d"
        for dir in [catalogDir, recordsDir, guestDir] {
            try? FileManager.default.createDirectory(
                atPath: dir, withIntermediateDirectories: true)
        }
        setenv("STARLING_CATALOG_DIR", catalogDir, 1)
        setenv("STARLING_APP_RECORDS", recordsDir, 1)
        setenv("STARLING_GUEST_APP_RECORDS", guestDir, 1)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(
            atPath: (catalogDir as NSString).deletingLastPathComponent)
        unsetenv("STARLING_CATALOG_DIR")
        unsetenv("STARLING_APP_RECORDS")
        unsetenv("STARLING_GUEST_APP_RECORDS")
        super.tearDown()
    }

    private func writeGuestRecord(_ name: String, _ body: String) {
        try? body.write(toFile: guestDir + "/" + name + ".app",
                        atomically: true, encoding: .utf8)
    }

    private func writeCatalog(_ name: String, _ body: String) {
        try? body.write(toFile: catalogDir + "/" + name + ".app",
                        atomically: true, encoding: .utf8)
    }

    private func writeRecord(_ name: String, _ body: String) {
        try? body.write(toFile: recordsDir + "/" + name + ".app",
                        atomically: true, encoding: .utf8)
    }

    private func reloaded() -> [AppRecord] {
        AppRegistry.shared.reload()
        return AppRegistry.shared.apps
    }

    // MARK: Loading and ordering

    /// A guest app's record is written by the shell, not shipped, and has no
    /// catalog entry to hang off — so the loader must enumerate the guest
    /// directory itself, treat the record as self-describing, and count it
    /// installed. A catalog id that collides keeps the catalog's record.
    func testGuestAppRecordsLoadStandaloneAndInstalled() {
        writeCatalog("windows", """
            [Starling App]
            Id=windows
            Name=Windows
            Kind=vm
            Domain=windows
            Order=230
            """)
        writeGuestRecord("guest-windows-notepad", """
            [Starling App]
            Id=guest-windows-notepad
            Name=Notepad
            Kind=guest-app
            Domain=windows
            Exec=Microsoft.WindowsNotepad_8wekyb3d8bbwe!App
            Order=900
            """)
        writeGuestRecord("windows", """
            [Starling App]
            Id=windows
            Name=Impostor
            Kind=guest-app
            Domain=windows
            Exec=nothing
            """)
        writeGuestRecord("not-a-guest-app", """
            [Starling App]
            Id=not-a-guest-app
            Name=Sneaky host record
            Kind=host
            Exec=evil
            """)
        let apps = reloaded()
        XCTAssertEqual(apps.map(\.id), ["windows", "guest-windows-notepad"])
        let notepad = apps[1]
        XCTAssertEqual(notepad.kind, .guestApp)
        XCTAssertTrue(notepad.installed)
        XCTAssertEqual(notepad.domain, "windows")
        XCTAssertEqual(notepad.exec, "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App")
        XCTAssertTrue(notepad.matches(appId: "guest-windows-notepad"),
                      "a window whose wmClass is the record id belongs to it")
        XCTAssertEqual(apps[0].name, "Windows", "the catalog wins an id collision")
        XCTAssertNil(notepad.installRecipe, "nothing for the store to install")
    }

    func testLoadsCatalogInOrder() {
        writeCatalog("b", "[Starling App]\nId=b\nName=Bee\nOrder=20\n")
        writeCatalog("a", "[Starling App]\nId=a\nName=Ay\nOrder=10\n")
        XCTAssertEqual(reloaded().map { $0.id }, ["a", "b"])
    }

    func testRecordsWithoutOrderSortLastByName() {
        writeCatalog("z", "[Starling App]\nId=z\nName=Alpha\n")
        writeCatalog("y", "[Starling App]\nId=y\nName=Beta\n")
        writeCatalog("a", "[Starling App]\nId=a\nName=First\nOrder=1\n")
        XCTAssertEqual(reloaded().map { $0.id }, ["a", "z", "y"])
    }

    /// UrlSchemes= parses as a semicolon list; absent means an empty list,
    /// and the xdg-open shim's grep and this parse must agree on the format.
    func testUrlSchemesParseAsList() {
        writeCatalog("web", "[Starling App]\nId=web\nName=Web\nUrlSchemes=http;https\n")
        writeCatalog("plain", "[Starling App]\nId=plain\nName=Plain\n")
        let apps = reloaded()
        XCTAssertEqual(apps.first { $0.id == "web" }?.urlSchemes, ["http", "https"])
        XCTAssertEqual(apps.first { $0.id == "plain" }?.urlSchemes, [])
    }

    // MARK: Installed-ness

    /// An app-install record is what "the store put it there" means, and it
    /// alone is enough — the binary may live somewhere Bins does not list.
    func testRecordAloneMarksAppInstalled() {
        writeCatalog("ghost", "[Starling App]\nId=ghost\nName=Ghost\n"
                            + "Bins=/definitely/not/here\n")
        XCTAssertFalse(reloaded().first!.installed)

        writeRecord("ghost", "[Starling App]\nId=ghost\nWmClass=ghost\n")
        XCTAssertTrue(reloaded().first!.installed)
    }

    /// Installed by hand, outside the store: no record, but the binary is
    /// there. This is every app that predates the registry.
    func testBinsProbeCoversAppsInstalledOutsideTheStore() {
        writeCatalog("sh", "[Starling App]\nId=sh\nName=Shell\nBins=/bin/sh\n")
        XCTAssertTrue(reloaded().first!.installed)
    }

    func testRecordFieldsOverrideCatalogHints() {
        writeCatalog("app", """
            [Starling App]
            Id=app
            Name=App
            Bins=/bin/sh
            WmClass=catalog-guess
            """)
        writeRecord("app", """
            [Starling App]
            Id=app
            WmClass=host-truth
            Version=1.2.3
            """)
        let record = reloaded().first!
        XCTAssertEqual(record.version, "1.2.3")
        // The host's answer is tried first.
        XCTAssertEqual(record.wmClasses.first, "host-truth")
        // ...without losing the catalog's fallback.
        XCTAssertTrue(record.matches(appId: "catalog-guess"))
    }

    /// A path that isn't there must not be handed out: the shell would attempt
    /// a decode per launch and fall back to the glyph anyway.
    func testMissingIconIsDropped() {
        writeCatalog("app", "[Starling App]\nId=app\nName=App\nBins=/bin/sh\n"
                          + "Icon=/no/such/icon.png\n")
        XCTAssertNil(reloaded().first!.iconPath)

        writeCatalog("app", "[Starling App]\nId=app\nName=App\nBins=/bin/sh\n"
                          + "Icon=/bin/sh\n")
        XCTAssertEqual(reloaded().first!.iconPath, "/bin/sh")
    }

    // MARK: Lookup

    func testLookupByAppIdAndTitle() {
        writeCatalog("intellij", """
            [Starling App]
            Id=intellij
            Name=IntelliJ IDEA
            Bins=/bin/sh
            WmClass=jetbrains-idea
            """)
        writeCatalog("zoom", """
            [Starling App]
            Id=zoom
            Name=Zoom
            Bins=/bin/sh
            TitleMatch=Zoom
            """)
        _ = reloaded()
        XCTAssertEqual(AppRegistry.shared.app(forAppId: "jetbrains-idea")?.id,
                       "intellij")
        XCTAssertEqual(AppRegistry.shared.app(forTitle: "Zoom Meeting")?.id, "zoom")
        // The case title matching cannot serve, and must not pretend to.
        XCTAssertNil(AppRegistry.shared.app(forTitle: "untitled – Main.java"))
    }

    func testDefaultDockIsOrderedAndInstalledOnly() {
        writeCatalog("second", "[Starling App]\nId=second\nName=Second\n"
                             + "Bins=/bin/sh\nDock=2\n")
        writeCatalog("first", "[Starling App]\nId=first\nName=First\n"
                            + "Bins=/bin/sh\nDock=1\n")
        writeCatalog("absent", "[Starling App]\nId=absent\nName=Absent\n"
                             + "Bins=/definitely/not/here\nDock=3\n")
        _ = reloaded()
        XCTAssertEqual(AppRegistry.shared.defaultDock.map { $0.id },
                       ["first", "second"])
    }

    // MARK: Parsing helpers

    func testWindowGeometryParsing() {
        let geometry = AppRegistry.geometry("100,60,800,592")
        XCTAssertEqual(geometry?.x, 100)
        XCTAssertEqual(geometry?.height, 592)
        XCTAssertNil(AppRegistry.geometry("100,60,800"))
        XCTAssertNil(AppRegistry.geometry("a,b,c,d"))
        XCTAssertNil(AppRegistry.geometry(nil))
    }

    /// A binary that has been replaced or deleted under a live process is
    /// reported by the kernel as "/path (deleted)". Missing that is how a
    /// running app gets uninstalled out from under itself.
    func testDeletedSuffixIsStrippedFromExePaths() {
        XCTAssertEqual(AppRegistry.stripDeleted("/usr/bin/gimp-3.2 (deleted)"),
                       "/usr/bin/gimp-3.2")
        XCTAssertEqual(AppRegistry.stripDeleted("/usr/bin/gimp-3.2"),
                       "/usr/bin/gimp-3.2")
    }

    /// The running check must match whichever form the launcher exec'd:
    /// /usr/bin/gimp is a symlink to gimp-3.2.
    func testRunningMatchesEitherTheLinkOrItsTarget() {
        writeCatalog("app", "[Starling App]\nId=app\nName=App\nBins=/bin/sh\n")
        _ = reloaded()
        XCTAssertEqual(AppRegistry.shared.runningAppIds(given: ["/bin/sh"]),
                       ["app"])
        XCTAssertEqual(
            AppRegistry.shared.runningAppIds(given: [AppRegistry.resolve("/bin/sh")]),
            ["app"])
        XCTAssertTrue(
            AppRegistry.shared.runningAppIds(given: ["/usr/bin/something"]).isEmpty)
    }

    // MARK: PRIME render offload (Gpu=)

    /// `Gpu=discrete` is the whole of the per-app offload policy: the record
    /// says where the app renders, and the launcher reads nothing else.
    func testDiscreteGpuIsReadFromTheRecord() {
        writeCatalog("dis", "[Starling App]\nId=dis\nName=Dis\nGpu=discrete\n")
        writeCatalog("int", "[Starling App]\nId=int\nName=Int\n")
        let apps = reloaded()
        XCTAssertEqual(apps.first { $0.id == "dis" }?.discreteGpu, true)
        XCTAssertEqual(apps.first { $0.id == "int" }?.discreteGpu, false,
                       "a record with no Gpu= key must not opt into the discrete GPU")
    }

    /// Everything that is not exactly `discrete` means the integrated GPU, and
    /// means it silently — the app launches and renders, just on the other
    /// card. That is precisely why the value cannot be validated here and is
    /// checked statically instead: `test/lint.py` compares the literal across
    /// the registry, the shell and app-run.sh, so a typo fails the build rather
    /// than shipping as a performance mystery. These cases pin the parse that
    /// lint is protecting.
    func testAnythingButDiscreteMeansIntegrated() {
        for value in ["Discrete", "DISCRETE", "dedicated", "nvidia", "true", "1", ""] {
            writeCatalog("app", "[Starling App]\nId=app\nName=App\nGpu=\(value)\n")
            XCTAssertEqual(reloaded().first { $0.id == "app" }?.discreteGpu, false,
                           "Gpu=\(value.isEmpty ? "<empty>" : value) must not read as discrete")
        }
    }

    /// Where the app renders is *catalog policy*, not an installed fact, so
    /// unlike WmClass/Icon/DesktopFile/Version an install record does not
    /// override it. The split is deliberate: a record carries what only exists
    /// once the app is on disk and app-install resolved it, and nothing about
    /// installing Blender discovers which GPU it ought to prefer. Pinned
    /// because the asymmetry is invisible at the call site — `discreteGpu`
    /// reads from the catalog keyfile beside a dozen fields that consult the
    /// record, and "make it overridable" is a one-word edit someone will
    /// reach for without noticing it changes where policy lives.
    func testGpuIsCatalogPolicyAndNotOverriddenByARecord() {
        writeCatalog("app", "[Starling App]\nId=app\nName=App\nBins=/bin/sh\n")
        writeRecord("app", "[Starling App]\nId=app\nWmClass=host-truth\nGpu=discrete\n")
        let record = reloaded().first { $0.id == "app" }
        XCTAssertEqual(record?.discreteGpu, false,
                       "Gpu= in an install record must not turn on offload")
        // The record still wins where it is supposed to, so this is a
        // deliberate exclusion rather than the merge being skipped entirely.
        XCTAssertEqual(record?.wmClasses.first, "host-truth")
    }
}
