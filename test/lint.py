#!/usr/bin/env python3
"""Static checks for the Starling desktop — no build, no GPU, under a second.

    test/lint.py [-v]

This tier exists because of a specific failure mode: a fact about an app, or a
callback between C and Swift, that is declared in one place and silently not
honoured in another. Nothing crashes, nothing logs, and the symptom shows up
much later as "that one app is broken". Three instances of it have cost real
time so far (the wl_shm commit callback, the app_id callback, and a dock that
matched window titles because it never saw app_id).

So the checks here are all of one shape: two places that must agree, compared.
Nothing here needs a compositor, a GPU, or a build — run it on every change.
"""

import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
CATALOG = REPO / "registry" / "catalog.d"

VERBOSE = "-v" in sys.argv

failures: list[tuple[str, str]] = []
notes: list[tuple[str, str]] = []


def fail(check: str, msg: str) -> None:
    failures.append((check, msg))


def note(check: str, msg: str) -> None:
    notes.append((check, msg))


def ok(msg: str) -> None:
    if VERBOSE:
        print(f"    ok  {msg}")


# ── key files ────────────────────────────────────────────────────────────────

def parse_keyfile(path: Path, group: str | None = None) -> dict[str, str]:
    """First-group-wins key file parse, matching KeyFile.swift."""
    out: dict[str, str] = {}
    current = None
    first = None
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            continue
        if "=" not in line:
            continue
        if group is not None:
            if current != group:
                continue
        elif first is not None and current != first:
            continue
        if first is None:
            first = current
        key, value = line.split("=", 1)
        out.setdefault(key.strip(), value.strip())
    return out


def semicolon_list(value: str) -> list[str]:
    return [p.strip() for p in value.split(";") if p.strip()]


# ── shell-script recipe tables ───────────────────────────────────────────────

def case_blocks(path: Path, selector: str) -> dict[str, str]:
    """label -> body, for every `case <selector> in` block in a shell script.

    Bodies matter as well as labels: app-install.sh has branches that exist to
    *refuse* (firefox and chromium, which Starling deliberately does not
    offer), and those must not be mistaken for install recipes.
    """
    blocks: dict[str, str] = {}
    in_block = False
    current: list[str] = []
    labels: list[str] = []

    def flush() -> None:
        body = "\n".join(current)
        for label in labels:
            blocks[label] = blocks.get(label, "") + body

    for line in path.read_text().splitlines():
        stripped = line.strip()
        if re.match(rf'case\s+{re.escape(selector)}\s+in\b', stripped):
            in_block = True
            continue
        if not in_block:
            continue
        if stripped.startswith("esac"):
            flush()
            labels, current = [], []
            in_block = False
            continue
        m = re.match(r'^([A-Za-z0-9_|*.-]+)\)', stripped)
        if m:
            flush()
            labels = [a for a in m.group(1).split("|") if a and a != "*"]
            # A one-liner puts the whole recipe after the label on the same
            # line: `blender)   inst blender ;;`
            current = [stripped[m.end():]]
            continue
        current.append(line)
    flush()
    return blocks


def install_recipe_names(path: Path) -> set[str]:
    """Labels of app-install.sh that actually install something."""
    installs = ("inst ", "vendor_deb ", "vendor_repo ", "apt-get install",
                "tar -x", "fetch ")
    return {label for label, body in case_blocks(path, '"$NAME"').items()
            if any(token in body for token in installs)}


# ── check: the app catalog ───────────────────────────────────────────────────

def swift_case_strings(path: Path, func_signature: str) -> set[str]:
    """String literals of `case "x":` inside one Swift function — used to read
    a vocabulary out of the code that owns it, instead of restating it here."""
    text = path.read_text()
    start = text.find(func_signature)
    if start < 0:
        return set()
    # Crude but adequate: stop at the function's closing brace column.
    body = text[start:]
    end = body.find("\n    }")
    if end > 0:
        body = body[:end]
    return set(re.findall(r'case\s+"([^"]+)"', body))


def check_catalog() -> None:
    check = "catalog"
    records = sorted(CATALOG.glob("*.app"))
    if not records:
        fail(check, f"no catalog records found in {CATALOG}")
        return

    # Vocabularies read from the code that defines them, so adding a glyph in
    # the shell does not make this lint wrong.
    glyphs = swift_case_strings(
        REPO / "shell/Sources/DesktopShellApp/Shell/DesktopShell.swift",
        "static func iconType(named name: String) -> IconType {")
    glyphs |= swift_case_strings(
        REPO / "apps/AppStoreApp/Sources/AppStoreApp/AppStoreApp.swift",
        "private func iconKind(_ glyph: String) -> StoreIconKind {")
    # The painter's fallback: every record that wants no special shape.
    glyphs.add("externalApp")
    if not glyphs:
        fail(check, "could not read the glyph vocabulary out of the Swift sources")

    kinds = {"first-party", "host", "android", "x11"}
    install_recipes = install_recipe_names(REPO / "build/app-install.sh")
    run_recipes = set(case_blocks(REPO / "build/app-run.sh", '"$NAME"'))

    seen_order: dict[int, str] = {}
    seen_dock: dict[int, str] = {}
    catalog_installs: set[str] = set()

    for path in records:
        rid = path.stem
        kf = parse_keyfile(path, group="Starling App")
        if not kf:
            fail(check, f"{path.name}: no [Starling App] group / unparseable")
            continue

        if kf.get("Id", rid) != rid:
            fail(check, f"{path.name}: Id={kf.get('Id')!r} does not match filename")
        if not kf.get("Name"):
            fail(check, f"{path.name}: missing Name")

        kind = kf.get("Kind", "host")
        if kind not in kinds:
            fail(check, f"{path.name}: Kind={kind!r} not one of {sorted(kinds)}")

        glyph = kf.get("Glyph", "externalApp")
        if glyph not in glyphs:
            fail(check, f"{path.name}: Glyph={glyph!r} is drawn by nothing "
                        f"(known: {', '.join(sorted(glyphs))})")

        colour = kf.get("Color", "")
        if colour and not re.fullmatch(r"[0-9A-Fa-f]{6}", colour):
            fail(check, f"{path.name}: Color={colour!r} is not RRGGBB")

        for key, table in (("Order", seen_order), ("Dock", seen_dock)):
            if key not in kf:
                continue
            try:
                value = int(kf[key])
            except ValueError:
                fail(check, f"{path.name}: {key}={kf[key]!r} is not an integer")
                continue
            if value in table:
                fail(check, f"{path.name}: {key}={value} collides with {table[value]}")
            table[value] = path.name

        for binary in semicolon_list(kf.get("Bins", "")):
            if not binary.startswith("/"):
                fail(check, f"{path.name}: Bins entry {binary!r} is not absolute")

        # An app the store can install must be installable and detectable.
        recipe = kf.get("Install")
        if recipe:
            catalog_installs.add(recipe)
            if recipe not in install_recipes:
                fail(check, f"{path.name}: Install={recipe!r} has no recipe in "
                            "build/app-install.sh")
            if kind == "host" and not kf.get("Bins"):
                fail(check, f"{path.name}: installable host app declares no Bins, "
                            "so nothing can tell whether it is installed")

        exec_name = kf.get("Exec", rid)
        if kind == "host" and exec_name not in run_recipes:
            fail(check, f"{path.name}: Exec={exec_name!r} has no recipe in "
                        "build/app-run.sh — the launcher would do nothing")
        if kind == "first-party":
            if not (REPO / "apps" / exec_name).is_dir():
                fail(check, f"{path.name}: Exec={exec_name!r} is not a package "
                            "under apps/")
            window = kf.get("Window", "")
            if len(semicolon_list(window.replace(",", ";"))) != 4:
                fail(check, f"{path.name}: first-party app needs Window=x,y,w,h "
                            f"(got {window!r})")

        # RenameWindows can only fire through one of these.
        if kf.get("RenameWindows") == "1" and not (kf.get("TitleMatch")
                                                   or kf.get("WmClass")):
            fail(check, f"{path.name}: RenameWindows=1 but nothing identifies "
                        "its windows (needs TitleMatch or WmClass)")
        ok(f"{path.name}")

    # The reverse direction: a recipe nothing in the desktop offers. This is
    # how mpv/vlc/libreoffice/obs became installable-but-invisible.
    unlisted = set()
    m = re.search(r'^UNLISTED="([^"]*)"',
                  (REPO / "build/app-install.sh").read_text(), re.M)
    if m:
        unlisted = set(m.group(1).split())
    orphans = install_recipes - catalog_installs - unlisted
    if orphans:
        fail(check, "app-install recipes with no catalog record and not listed "
                    f"in UNLISTED: {', '.join(sorted(orphans))}")
    stale = unlisted & catalog_installs
    if stale:
        fail(check, "apps in app-install's UNLISTED that do have a catalog "
                    f"record: {', '.join(sorted(stale))}")

    print(f"  catalog: {len(records)} records checked")


# ── check: C callbacks the Swift side must register ──────────────────────────

# Declared and fired, but deliberately not registered. Each entry needs a
# reason; a bare name is not enough, because the whole point of this check is
# that an unregistered callback is invisible.
KNOWN_UNREGISTERED = {
    "wayland_server_on_toplevel_resize_request":
        "xdg_toplevel set_max_size and set_min_size both fire this ONE callback "
        "with no way to tell which, so registering it as-is would apply a "
        "minimum as a maximum. Client size constraints are ignored until the C "
        "side splits it in two.",
}


def check_wayland_callbacks() -> None:
    """Every `wayland_server_on_*` the compositor declares must be registered
    by the Swift side.

    This is the check that would have caught the wl_shm bug (every software
    client composited as nothing) and the app_id bug (no dock icon for any
    third-party app). In both cases the C was complete — declared, defined,
    called — and the Swift setter was simply never written. There is no
    warning, no crash, and no log line for that.
    """
    check = "wayland-callbacks"
    header = REPO / "shell/Sources/WaylandServer/include/wayland_server.h"
    declared = set(re.findall(r"\bwayland_server_on_(\w+)\s*\(", header.read_text()))
    if not declared:
        fail(check, f"no wayland_server_on_* declarations found in {header}")
        return

    swift = " ".join(p.read_text() for p in
                     (REPO / "shell/Sources/DesktopShellApp").rglob("*.swift"))
    for name in sorted(declared):
        full = f"wayland_server_on_{name}"
        if full in swift:
            ok(full)
        elif full in KNOWN_UNREGISTERED:
            note(check, f"{full} is declared and fired but not registered — "
                        f"{KNOWN_UNREGISTERED[full]}")
        else:
            fail(check, f"{full} is declared in wayland_server.h but never "
                        "registered in Swift: the compositor will fire it into "
                        "a NULL pointer and drop whatever it carries, silently")
    gaps = KNOWN_UNREGISTERED.keys() & {f"wayland_server_on_{n}" for n in declared}
    print(f"  wayland callbacks: {len(declared)} declared, {len(gaps)} known gap(s)")


# ── check: the engine's C API header and the sdk's copy agree ────────────────

def check_engine_header_mirror() -> None:
    """fl_drm_view.h exists twice — the engine compiles the original, Swift
    imports the copy in sdk/Sources/FlutterDRMBridge — and nothing but this
    check notices when they drift. A function added on one side only either
    fails to link (loud, lucky) or silently calls the old ABI (unlucky).

    Same file, same trap, second shape: an `fl_drm_view_set_*_callback` the
    engine declares but no Swift ever registers fires into a NULL pointer
    and drops whatever it carries — the wl_shm lesson, one layer down.
    """
    check = "engine-header"
    engine_header = (REPO / "engine/src/flutter/shell/platform/linux_drm"
                     / "fl_drm_view.h")
    sdk_header = (REPO / "sdk/Sources/FlutterDRMBridge/include/engine"
                  / "fl_drm_view.h")
    if not engine_header.exists() or not sdk_header.exists():
        note(check, "engine/ or sdk/ checkout not present — skipped "
                    "(run bootstrap.sh)")
        return
    if engine_header.read_text() != sdk_header.read_text():
        fail(check, "fl_drm_view.h differs between the engine and the sdk "
                    "copy Swift imports — copy the engine's over "
                    "sdk/Sources/FlutterDRMBridge/include/engine/")
        return
    ok("fl_drm_view.h engine/sdk copies identical")

    declared = set(re.findall(r"\bfl_drm_view_(set_\w*_callback)\s*\(",
                              sdk_header.read_text()))
    swift = " ".join(p.read_text() for p in
                     (REPO / "shell/Sources/DesktopShellApp").rglob("*.swift"))
    for name in sorted(declared):
        full = f"fl_drm_view_{name}"
        if full in swift:
            ok(full)
        else:
            fail(check, f"{full} is declared in fl_drm_view.h but never "
                        "called in the shell: the engine will fire it into "
                        "a NULL pointer and drop whatever it carries, silently")
    print(f"  engine header: mirrored, {len(declared)} callback setter(s)")


# ── check: builder overloads track the initializers they wrap ────────────────

def _split_params(text: str) -> list[str]:
    """Split a Swift parameter list on top-level commas."""
    out, depth, current = [], 0, ""
    for ch in text:
        if ch in "([<{":
            depth += 1
        elif ch in ")]>}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append(current)
            current = ""
        else:
            current += ch
    if current.strip():
        out.append(current)
    return [p.strip() for p in out if p.strip()]


def _parse_param(param: str) -> tuple[str, str, str]:
    """`padding: EdgeInsets = EdgeInsets(...)` -> (name, type, default).

    Types are normalised so that `any P` and a bare `P` compare equal — they
    denote the same existential, and the ported sources still use the older
    spelling in places.
    """
    name, _, rest = param.partition(":")
    name = name.strip().split()[-1]           # drop an external label
    depth, cut = 0, None
    for i, ch in enumerate(rest):
        if ch in "([<{":
            depth += 1
        elif ch in ")]>}":
            depth -= 1
        elif ch == "=" and depth == 0:
            cut = i
            break
    type_str = (rest if cut is None else rest[:cut])
    default = "" if cut is None else rest[cut + 1:]
    type_str = re.sub(r"\bany\s+", "", " ".join(type_str.split()))
    return name, type_str, " ".join(default.split())


def _param_map(text: str) -> dict[str, tuple[str, str]]:
    out = {}
    for p in _split_params(text):
        if p.startswith("@"):                  # builder-annotated closure
            continue
        name, type_str, default = _parse_param(p)
        out[name] = (type_str, default)
    return out


def _balanced(src: str, start: int, opener: str = "(", closer: str = ")") -> str:
    """Return the text inside the delimiters beginning at `start`."""
    depth, i = 0, start
    while i < len(src):
        if src[i] == opener:
            depth += 1
        elif src[i] == closer:
            depth -= 1
            if depth == 0:
                return src[start + 1:i]
        i += 1
    return ""


def check_result_builders() -> None:
    """Every trailing-closure overload must carry the same parameters as the
    ported initializer it delegates to.

    `sdk/Sources/Flutter/Widgets/ResultBuilders.swift` restates each widget's
    parameter list so the block form can accept it. That is a second copy of a
    fact defined elsewhere, which is the failure mode this whole tier exists
    for: add `spacing:` to the ported `Row.init` and the builder overload keeps
    compiling, keeps working, and silently cannot express spacing. Nothing
    warns — the call site just has no such argument, and the tree it builds is
    quietly not the one the author asked for.
    """
    check = "widget-builders"
    overlay = REPO / "sdk/Sources/Flutter/Widgets/ResultBuilders.swift"
    if not overlay.exists():
        return
    src = overlay.read_text()

    sources = [p for p in (REPO / "sdk/Sources/Flutter").rglob("*.swift")
               if p != overlay]
    corpus = {p: p.read_text() for p in sources}

    def ported_signatures(cls: str, member: str) -> list[dict[str, tuple[str, str]]]:
        """Parameter maps of every `init` (or named static func) declared on `cls`."""
        sigs = []
        for text in corpus.values():
            m = re.search(r"^(?:public|open)\s+(?:final\s+)?class\s+%s\s*[:{]"
                          % re.escape(cls), text, re.M)
            if not m:
                continue
            body_start = text.index("{", m.start())
            body = _balanced(text, body_start, "{", "}")
            if member == "init":
                pattern = r"(?:public\s+)?(?:convenience\s+|override\s+)*init\s*\("
            else:
                pattern = r"public\s+static\s+func\s+%s\s*\(" % re.escape(member)
            for hit in re.finditer(pattern, body):
                paren = body.index("(", hit.end() - 1)
                sigs.append(_param_map(_balanced(body, paren)))
        return sigs

    checked = 0
    for ext in re.finditer(r"^extension\s+(\w+)\s*\{", src, re.M):
        cls = ext.group(1)
        block = _balanced(src, src.index("{", ext.start()), "{", "}")
        members = list(re.finditer(
            r"public\s+convenience\s+init\s*\(|public\s+static\s+func\s+(\w+)\s*\(",
            block))
        for hit in members:
            member = hit.group(1) or "init"
            paren = block.index("(", hit.end() - 1)
            overload = _param_map(_balanced(block, paren))
            label = f"{cls}.{member}" if member != "init" else f"{cls}.init"

            candidates = ported_signatures(cls, member)
            if not candidates:
                fail(check, f"{label}: no ported declaration found to compare "
                            "against — the overlay may be wrapping a member "
                            "that has been renamed or removed")
                continue

            # The ported form differs from the overload by exactly the child
            # parameter, which the builder closure replaces.
            best, best_diff = None, None
            for sig in candidates:
                stripped = {k: v for k, v in sig.items()
                            if k not in ("child", "children")}
                if stripped == overload:
                    best = sig
                    break
                missing = set(stripped) - set(overload)
                extra = set(overload) - set(stripped)
                changed = {k for k in set(stripped) & set(overload)
                           if stripped[k] != overload[k]}
                score = len(missing) + len(extra) + len(changed)
                if best_diff is None or score < best_diff[0]:
                    best_diff = (score, missing, extra, changed, stripped)
            if best is not None:
                ok(label)
                checked += 1
                continue

            _, missing, extra, changed, stripped = best_diff
            parts = []
            if missing:
                parts.append("missing " + ", ".join(
                    f"`{k}: {stripped[k][0]}`" for k in sorted(missing)))
            if extra:
                parts.append("has no counterpart for " + ", ".join(
                    f"`{k}`" for k in sorted(extra)))
            if changed:
                parts.append("differs on " + ", ".join(
                    f"`{k}` ({stripped[k][0]}"
                    f"{' = ' + stripped[k][1] if stripped[k][1] else ''}"
                    f" vs {overload[k][0]}"
                    f"{' = ' + overload[k][1] if overload[k][1] else ''})"
                    for k in sorted(changed)))
            fail(check, f"{label} has drifted from the initializer it wraps: "
                        + "; ".join(parts)
                        + " — the block form silently cannot express it")
            checked += 1

    print(f"  widget builders: {checked} overload(s) checked")


# ── check: every window-chrome callback is wired in every tree ───────────────

# Call sites that deliberately leave a chrome callback nil. Each needs a
# reason, for the same purpose as KNOWN_UNREGISTERED above: a nil callback
# draws a perfectly normal button that does nothing, so "it looks fine" is
# never evidence.
CHROME_EXEMPT = {
    ("DesktopShell.swift", "_makeOverviewWindow"): {
        "onMinimize":
            "the scale-to-fit virtual-desktop harness has no dock to zoom "
            "into and skips the lifecycle-animation machinery entirely; its "
            "windows exist to be dragged across simulated seams.",
        "isTopBarRevealed":
            "the same harness renders every output shrunk onto one panel, so "
            "there is no per-output top edge to hover; it never puts a window "
            "in fullscreen either.",
    },
}

# Anything in DesktopWindow's init named on* that is NOT window chrome.
CHROME_NOT_A_CALLBACK: set[str] = set()

# Not an on* callback, but the identical trap: it defaults to false, and a
# tree that omits it can never reveal a fullscreen window's title bar — which
# leaves that window with no traffic lights and no way out of fullscreen on
# the monitor it is on.
CHROME_EXTRA_REQUIRED = {"isTopBarRevealed"}


def _strip_swift_noise(src: str) -> str:
    """Blank out comments and string literals, preserving offsets, so paren
    and comma counting can't be thrown by a `(macOS)` in a comment."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        two = src[i:i + 2]
        if two == "//":
            while i < n and src[i] != "\n":
                out[i] = " "
                i += 1
        elif two == "/*":
            depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            while i < n and depth:
                if src[i:i + 2] == "/*":
                    depth += 1
                    out[i] = out[i + 1] = " "
                    i += 2
                elif src[i:i + 2] == "*/":
                    depth -= 1
                    out[i] = out[i + 1] = " "
                    i += 2
                else:
                    if src[i] != "\n":
                        out[i] = " "
                    i += 1
        elif src[i] == '"':
            out[i] = " "
            i += 1
            while i < n and src[i] != '"':
                if src[i] == "\\" and i + 1 < n:
                    out[i] = out[i + 1] = " "
                    i += 2
                    continue
                if src[i] != "\n":
                    out[i] = " "
                i += 1
            if i < n:
                out[i] = " "
                i += 1
        else:
            i += 1
    return "".join(out)


def _top_level_labels(src: str, open_paren: int) -> tuple[set[str], int]:
    """Argument labels passed at the top level of the call whose `(` is at
    `open_paren`. Returns (labels, index just past the matching `)`)."""
    labels: set[str] = set()
    depth = 0
    i, n = open_paren, len(src)
    chunk_start = open_paren + 1
    chunks: list[str] = []
    while i < n:
        c = src[i]
        if c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
            if depth == 0:
                chunks.append(src[chunk_start:i])
                i += 1
                break
        elif c == "," and depth == 1:
            chunks.append(src[chunk_start:i])
            chunk_start = i + 1
        i += 1
    for chunk in chunks:
        m = re.match(r"\s*(\w+)\s*:", chunk)
        if m:
            labels.add(m.group(1))
    return labels, i


def check_window_chrome() -> None:
    """Every `DesktopWindow(...)` call site must pass every chrome callback
    `DesktopWindow` accepts.

    The shell renders window chrome in more than one widget tree — the primary
    shell's build, and one `SecondaryOutputScreen` per extra monitor, each in
    its own Flutter view. Every callback is optional and defaults to nil, so a
    tree that forgets one gets a button that draws in the right place, hovers,
    presses, and does nothing at all.

    That is not hypothetical: the secondary-output screen passed only
    move/resize/raise, so all three traffic lights and the title-bar
    double-click were dead for any window dragged onto a second monitor —
    while being perfectly alive for the same window on the primary.
    """
    check = "window-chrome"
    shell_src = REPO / "shell/Sources/DesktopShellApp"
    widget = shell_src / "Window/DesktopWindow.swift"
    src = _strip_swift_noise(widget.read_text())

    m = re.search(r"\n    init\s*\(", src)
    if not m:
        fail(check, f"no init( found in {widget.name}")
        return
    accepted, _ = _top_level_labels(src, src.index("(", m.start()))
    required = {p for p in accepted
                if re.match(r"on[A-Z]", p)} - CHROME_NOT_A_CALLBACK
    if not required:
        fail(check, f"no on* callbacks found in {widget.name}'s init")
        return
    missing_extra = CHROME_EXTRA_REQUIRED - accepted
    if missing_extra:
        fail(check, f"{widget.name}'s init no longer accepts "
                    f"{', '.join(sorted(missing_extra))} — update "
                    "CHROME_EXTRA_REQUIRED to match")
        return
    required |= CHROME_EXTRA_REQUIRED

    sites = 0
    for path in sorted(shell_src.rglob("*.swift")):
        if path == widget:
            continue
        text = _strip_swift_noise(path.read_text())
        for hit in re.finditer(r"\bDesktopWindow\s*\(", text):
            passed, _ = _top_level_labels(text, text.index("(", hit.start()))
            # Name the call site by its enclosing func, for the exemption
            # table and for a message that says where to look.
            before = text[:hit.start()]
            fn = re.findall(r"\bfunc\s+(\w+)", before)
            where = fn[-1] if fn else "<top level>"
            exempt = CHROME_EXEMPT.get((path.name, where), {})
            sites += 1
            for cb in sorted(required - passed):
                if cb in exempt:
                    note(check, f"{path.name}:{where} leaves {cb} nil — "
                                f"{exempt[cb]}")
                elif cb in passed:
                    continue
                else:
                    line = before.count("\n") + 1
                    fail(check,
                         f"{path.name}:{line} ({where}) builds a DesktopWindow "
                         f"without {cb}: that control renders and hovers "
                         f"normally, and silently does nothing, for every "
                         f"window this tree draws")
            for cb in sorted(required & passed):
                ok(f"{path.name}:{where} {cb}")
    if sites == 0:
        fail(check, "no DesktopWindow call sites found — did the widget move?")
    print(f"  window chrome: {len(required)} callback(s) × {sites} call site(s)")


# ── check: PRIME render offload agrees end to end ────────────────────────────

def check_gpu_offload() -> None:
    """`Gpu=discrete` is a bare string compared in five independent places.

    A record says `Gpu=discrete`; the registry turns that into a bool with
    `kf.string("Gpu") == "discrete"`; the shell puts `STARLING_APP_GPU=discrete`
    in the child's environment; app-run.sh tests that variable and forwards it
    through bwrap. Every one of those is an exact match against a literal, and
    every one of them fails SILENTLY and identically: the app launches, renders
    on the integrated GPU, and nothing anywhere says why. `Gpu=Discrete` or a
    shell that grew a `dedicated` spelling the launcher never learned would look
    exactly like a machine with no discrete GPU.

    So compare the literals rather than trusting them, and read each out of the
    file that defines it — growing the vocabulary in all four places keeps this
    lint correct, changing it in three does not.
    """
    check = "gpu-offload"

    def literals(path: Path, pattern: str) -> set[str]:
        try:
            return set(re.findall(pattern, path.read_text()))
        except OSError:
            return set()

    # The value the registry accepts, out of the comparison itself.
    parsed = literals(REPO / "registry/Sources/StarlingRegistry/AppRegistry.swift",
                      r'kf\.string\("Gpu"\)\s*==\s*"([^"]+)"')
    # What the shell puts in the child environment.
    shell_env = literals(REPO / "shell/Sources/DesktopShellApp/Shell/DesktopShell.swift",
                         r'hostEnv\["STARLING_APP_GPU"\]\s*=\s*"([^"]+)"')
    # What app-run.sh acts on, and what it forwards through bwrap.
    run = REPO / "build/app-run.sh"
    run_tested = literals(run, r'"\$\{STARLING_APP_GPU:-\}"\s*=\s*"([^"]+)"')
    run_forwarded = literals(run, r'--setenv STARLING_APP_GPU (\S+)')

    sources = {
        "registry parses": parsed,
        "shell sets": shell_env,
        "app-run.sh tests": run_tested,
        "app-run.sh forwards": run_forwarded,
    }
    for label, values in sources.items():
        if not values:
            fail(check, f"could not read the offload value out of what {label} — "
                        "the code moved and this check is now blind")
            return

    if len({frozenset(v) for v in sources.values()}) != 1:
        detail = "; ".join(f"{label} {sorted(v)}" for label, v in sources.items())
        fail(check, f"the offload value disagrees across the chain: {detail}")
        return

    accepted = parsed
    ok(f"offload vocabulary agrees across {len(sources)} sites: {sorted(accepted)}")

    # And every record that asks for a GPU must ask for one that exists.
    asked = 0
    for path in sorted(CATALOG.glob("*.app")):
        kf = parse_keyfile(path, group="Starling App")
        if not kf or "Gpu" not in kf:
            continue
        asked += 1
        value = kf["Gpu"]
        if value not in accepted:
            fail(check, f"{path.name}: Gpu={value!r} is not a value anything "
                        f"acts on (known: {', '.join(sorted(accepted))}) — the "
                        "app would silently render on the integrated GPU")
        else:
            ok(f"{path.name}: Gpu={value}")
    print(f"  gpu offload: {len(sources)} sites agree, {asked} record(s) ask for a GPU")


# ── check: the scripts parse ─────────────────────────────────────────────────

def check_script_syntax() -> None:
    check = "syntax"
    count = 0
    # test/vm-harness is here for a reason: nothing runs those scripts except
    # the release gate, so a typo in one would otherwise surface at release
    # time, on a boot that takes half an hour to fail.
    for script in sorted((REPO / "build").glob("*.sh")) + \
                  sorted((REPO / "test/vm-harness").glob("*.sh")):
        # Check each script with the shell it actually declares: run-desktop.sh
        # and wechat-run.sh are bash and use arrays, which `sh -n` (dash)
        # rejects for syntax it simply does not have.
        shebang = script.read_text().split("\n", 1)[0]
        shell = "bash" if "bash" in shebang else "sh"
        result = subprocess.run([shell, "-n", str(script)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            fail(check, f"{script.name}: {result.stderr.strip()}")
        else:
            ok(script.name)
        count += 1
    for script in sorted((REPO / "build").glob("*.py")) + \
                  sorted((REPO / "test").glob("*.py")) + \
                  sorted((REPO / "test/vm-harness").glob("*.py")):
        result = subprocess.run([sys.executable, "-m", "py_compile", str(script)],
                                capture_output=True, text=True)
        if result.returncode != 0:
            fail(check, f"{script.name}: {result.stderr.strip()}")
        else:
            ok(script.name)
        count += 1
    print(f"  syntax: {count} scripts")


# ── main ─────────────────────────────────────────────────────────────────────

def main() -> int:
    print("starling lint")
    check_catalog()
    check_wayland_callbacks()
    check_engine_header_mirror()
    check_result_builders()
    check_window_chrome()
    check_gpu_offload()
    check_script_syntax()

    for check, msg in notes:
        print(f"\n  note [{check}] {msg}")
    if failures:
        print(f"\n{len(failures)} failure(s):")
        for check, msg in failures:
            print(f"  FAIL [{check}] {msg}")
        return 1
    print("\nall checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
