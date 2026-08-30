# catalog.d — every app the desktop knows about

One key file per app. This is the **only** place an app is declared: the
launcher, the dock, the App Store and `app-install` all read it. Adding an app
is adding a file here (plus a launch recipe in `build/app-run.sh` and an
install recipe in `build/app-install.sh` when it is a third-party host app).

Staged to `<share>/catalog.d`, installed to `/usr/share/starling/catalog.d`.

## Keys

| Key | Meaning |
|---|---|
| `Id` | app id — also the `app-run` / `app-install` name. Defaults to the filename. |
| `Name` | what the launcher label and dock tooltip say |
| `Kind` | `first-party` \| `host` \| `android` \| `x11` — how it launches |
| `Order` | launcher sort key |
| `Dock` | position in the default dock; absent = launcher-only until pinned |
| `Glyph` | painter fallback shape (an `IconType` case). Never a brand mark — see below |
| `Color` | tile base colour, `RRGGBB` |
| `Exec` | `app-run` recipe (host), executable name (first-party), `android-app` arg |
| `Install` | `app-install` recipe name; absent = the store cannot install it |
| `Bins` | `;`-separated paths whose existence means "installed" |
| `DesktopEntry` | `;`-separated `.desktop` basenames — where the icon and window class are read from |
| `WmClass` | `;`-separated app_id fallbacks, for apps that ship no `.desktop` |
| `TitleMatch` | `;`-separated title substrings — **only** for windows that carry no usable app_id |
| `RenameWindows` | `1` to display `Name` instead of the window's own title |
| `Gpu` | `discrete` to render on the discrete GPU when there is one (PRIME offload, docs/plans/prime.md); no-op on single-GPU machines |
| `Agent` | `1` if the app drives a computer-use agent — a new workspace offers to run it, and the agent it spawns is paired to that workspace by process ancestry |
| `Category` `Publisher` `Subtitle` `Size` `Description` | App Store copy |
| `DebUrl` `DebMarker` | sealed-image install (Starling OS), where there is no apt |

## Two things worth knowing

**`TitleMatch` is a last resort, not a fallback.** Matching a window to an app
by its title breaks for any app whose title is `<document> – <thing>`:
IntelliJ's project window is titled `untitled – Main.java` and contains no
"IntelliJ" anywhere. Use it only where there is genuinely no app_id — Zoom
(Qt/xcb on the in-tree X server), WeChat (alone inside a rootful Xwayland whose
window is titled `Xwayland on :N`), and Waydroid (one window for every Android
app, titled after whichever is foreground). Every real Wayland client sets
`xdg_toplevel.set_app_id`; use `DesktopEntry`/`WmClass` for those.

**No third-party artwork is shipped.** `Glyph` names a shape we draw
ourselves, deliberately by category — a browser gets a globe, not a coloured
disc. Real icons are read at runtime from the copy the user installed, through
the freedesktop lookup, because those marks are their owners' trademarks and
the apps' licences do not grant them.
