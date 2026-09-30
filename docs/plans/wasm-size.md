# The web module's size — plan

Status: **done, 2026-09-29**, the same day it was written: 60 MB → 11.6 MB
raw, 3.5 MB brotli. What was planned, what was measured and what turned out
differently are all below; "Where it landed" has the numbers.

## What the 60 MB is

Measured on the release build (`--strip-all`, `-O`), by wasm section and by
the linker's `--why-extract` and `llvm-nm -u` on our objects:

| Part | Size | Where it comes from |
|---|---|---|
| data | **37.1 MB** | ICU's data tables (`lib_FoundationICU.a`) |
| code: ICU (C++) | 2.4 MB | same |
| code: `Foundation` + `FoundationInternationalization` | 1.8 MB | the legacy NS layer and its ICU-backed formatters |
| code: `FoundationEssentials` + `_FoundationCollections` | 3.6 MB | Date, JSON, UUID, Data, AttributedString … |
| code: `_RegexParser` + `_StringProcessing` | 1.2 MB | one regex literal in `Foundation/Print.swift`, `NSRegularExpression` in `StackFrame.swift` |
| code: Swift stdlib and runtime | ~3.5 MB | |
| code: `Flutter` | 3.8 MB | the framework proper (174k lines) |
| code: everything else of ours | ~1.5 MB | bridge 0.5, CupertinoIcons 0.4 (1,322 icon constants), … |

**42 MB of the 60 are there because eleven kinds of call reach the legacy
`Foundation` module** — the `NSString`/`NSLock`/`Bundle` layer that
swift-corelibs kept — and that module's own object graph runs
`AffineTransform → DateFormatter → NSCalendar → FoundationInternationalization
→ ICU`, all of it, whether or not a date is ever formatted. Nothing of ours
calls Internationalization directly. The 96 references from our 57 objects:

| Calls | What |
|---|---|
| 40 | `String(format:)` (resolves to `String.init(format:locale:arguments:)`) |
| 9 | `FileHandle.standardError` and `.write` |
| 7 | `NSLock` |
| 12 | `StringProtocol` overloads the NS layer owns: `range(of:options:)`, `replacingOccurrences`, `trimmingCharacters(in:)`, `compare(_:options:locale:)`, `addingPercentEncoding`; `CharacterSet.whitespaces`, `.whitespacesAndNewlines`, `.urlPathAllowed` |
| 8 | Paths and files: `NSString.deletingLastPathComponent`, `.appendingPathComponent`, `.pathExtension`, `NSHomeDirectory()`, `Bundle.main`, `Bundle(path:)`, `FileHandle(forWritingAtPath:)` |
| 3 | `NSRegularExpression`, `Range(_:in:)` |
| 1 | `JSONSerialization` (in our own `FragmentProgram.swift`) |
| 5 | Bridging casts: `String`/`Set` `_bridgeToObjectiveC`, `NSNumber` |

`-Osize` alone is worth 1.8 MB of code (22.3 → 20.5) and nothing on data.
gzip takes the current 58 MB to 20 MB; ICU data does not compress well.

## Targets

| | raw | gzip | when |
|---|---|---|---|
| today | 60 MB | 20 MB | |
| after phase 1 | ≤ 20 MB | ≤ 6 MB | the legacy layer is gone |
| after phase 2 | ≤ 14 MB | ≤ 4 MB | code trimmed |

For scale: Flutter's own web build is skwasm (3.5 MB raw, ~1 MB gzip, which
we also ship) plus 1–2 MB of compiled Dart. We will not reach that with
Foundation in the module; ≤ 4 MB compressed for the framework is a page that
loads in a second or two on a normal connection, and is the goal.

## Where it landed

| | raw | gzip | brotli |
|---|---|---|---|
| before | 60.0 MB | 20.0 MB | |
| phase 1: legacy Foundation off the link | 20.3 MB | 6.0 MB | |
| phase 2: `-Osize` + `wasm-opt -Oz` | **11.6 MB** | 4.2 MB | **3.5 MB** |

Code by module in the final build (`wasm-size.py --by-module`, before
wasm-opt): Swift stdlib 4.8 MB, the framework 3.8, FoundationEssentials
2.5, the regex engine 1.2, `_FoundationCollections` 0.7, C++ 0.7, the bridge
0.5, CupertinoIcons 0.4. wasm-opt then takes 40% off the lot.

What differed from the plan:

- **Removing the references was not enough.** With every NS-layer call
  gone, `libFoundation.a` was still linked and ICU with it: the linker
  takes a generic specialization (`Dictionary<String,_>.find`) from the
  first archive that defines it, and `-lFoundation` precedes
  `-lFoundationEssentials` on the autolink line. Reordering is not
  possible from a manifest, so the legacy libraries are kept off the link
  with `-disable-autolink-library` (in `sdk/Package.swift`), and the gate
  proves nothing wanted them.
- **The archives are WMO buckets.** `libFoundationEssentials.a(Bundle+Stub.swift.obj)`
  contains no Bundle code in particular; symbols are spread across
  objects by the whole-module build. So "which member pulled what" is
  noise, and the 2.5 MB of Essentials that survives `--gc-sections` is
  kept alive by protocol conformance records, which the Swift runtime
  enumerates and the linker therefore retains, and which point at type
  descriptors, witness tables, methods. `-conditional-runtime-records`
  exists for this and does nothing on wasm (measured: identical bytes).
  LTO cannot help either — the archives are not bitcode (measured: 0.1 MB
  for a 50 s link). The Essentials code stays until Essentials goes,
  which means `Data`, `Date` and `ProcessInfo` go, and that is not this
  plan.
- **Shadowing an imported extension method is not shadowing.** A
  module-local `String(format:_: CVarArg...)` was *ambiguous* with
  Foundation's, and so was any fixed arity above one; only the
  one-argument form outranks the variadic. The framework's calls all pass
  one argument (the two that did not were split), so it holds — and
  `contains(_: String)` never won at all and became `containsSubstring`.
  Top-level types (`Timer`, `RunLoop`, `FileHandle`, `NSLock`) shadow
  cleanly.
- **`JSONDecoder` is 3 MB** (it parses ISO-8601 dates, which brings
  Calendar, which brings the regex engine); the one use, the shader-bundle
  JSON, has a forty-line parser of its own now.
- **wasm-opt was the biggest single lever after ICU**: 15.1 → 9.0 MB of
  code in ten seconds. `-Osize` was worth 1.8 MB. Both are in
  `build/web-app.sh`, wasm-opt optionally (`brew install binaryen`).

## Phase 0 — a gate, before any fix (½ day)

Nothing here holds unless the build says so, every time.

- `build/web-app.sh` prints the wasm's section sizes (data, code, custom)
  after staging, next to the byte count it prints now.
- `build/web-app.sh --check` links with `--why-extract` and fails if any
  member of `lib_FoundationICU.a`, `libFoundationInternationalization.a` or
  `libFoundation.a` was extracted, naming the first of our objects on each
  chain (the script that found the table above, made permanent). Also
  fails if `app.wasm` is over a budget written in the script; the budget is
  lowered as each phase lands and never raised.
- `test/run.sh` learns to run the check when the wasm SDK is installed, and
  to say `skipped` when it is not.

## Phase 1 — leave the legacy Foundation layer (2–3 days)

Goal: `libFoundation.a` is not extracted at all. Each step is verified by
the phase-0 check; the order is by how many references it removes.

1. **`String(format:)` — 40 sites.** Audit the format strings first
   (`grep -o 'String(format: "[^"]*"'`): expected to be `%d`, `%.Nf`, `%s`,
   `%02x` and `%@`, nothing exotic. Then a module-local `String.init(format:_
   arguments: CVarArg...)` in `Flutter/Foundation/WebSupport.swift` under
   `#if os(WASI)` that handles exactly those conversions in Swift (flags,
   width, precision, `d i u x X f e g s @ %`); a declaration in the module
   shadows the imported one, so no call site changes. `%@` on a non-string
   argument formats `String(describing:)`. Unsupported conversions are a
   `preconditionFailure` in debug and the raw specifier in release, so a
   new site is caught by the first build that runs it. The same for
   `FlutterSwiftBridge` (its own copy, or the shim moved into the bridge
   module and `@_exported`).
2. **`FileHandle.standardError` — 9 sites.** A module-local `FileHandle`
   with `standardError`, `standardOutput` and `write(_ data: Data)` over
   `fputs`/`write(2)` — the page turns fd 2 into `console.error` already.
3. **`NSLock` — 7 sites**: a module-local `NSLock` whose `lock`/`unlock`/
   `withLock` do nothing, with a comment saying why that is right (one
   thread). Check `NSCondition`/`NSRecursiveLock` are not also present.
4. **String and CharacterSet overloads — 12 sites.** These files import
   `Foundation` and the type checker picks the NS-backed overload.
   Per site, either the `FoundationEssentials` spelling (`trimmingCharacters`
   and `range(of:)` exist there without `locale`; `replacingOccurrences`
   becomes stdlib `replacing(_:with:)`; `compare(options:)` becomes a
   `lowercased()` comparison or `localizedStandardCompare` dropped), or,
   where the file needs nothing else from the NS layer,
   `#if os(WASI) import FoundationEssentials #else import Foundation #endif`
   at the top. Whichever leaves the file readable.
5. **Files and paths — 8 sites.** All in code that cannot mean anything in
   a tab: `MacosFilePanel`, `UserHome`, `CupertinoIcons.fontData`,
   `Assertions`' log file. `#if !os(WASI)` around the function bodies with
   an empty or `nil` result, not around whole files.
6. **`NSRegularExpression`** in `StackFrame.swift`: the frames are already
   `[]` on WASI (`Thread.callStackSymbols` is our stub), so the parser is
   dead code there; `#if !os(WASI)` it. **`JSONSerialization`** in
   `FragmentProgram.swift`: `JSONDecoder` with a small `Codable` type, which
   is `FoundationEssentials`, and is also just better.
7. **Bridging casts**: find the `as NSString` / `as? NSNumber` / `as NSSet`
   sites (five) and remove the cast; each has a plain-Swift spelling.
8. Re-run the check. Expect `data` to drop from 37 MB to under 1 MB and
   `code` by ~4 MB. Then verify CounterApp still runs, and eyeball text
   layout — `String(format:)` feeds some pixel arithmetic.

What this is not: not dropping `import Foundation` from 89 files. The
umbrella import costs nothing by itself; only references do.

## Phase 2 — the code (2–3 days, each item measured separately)

Take each in turn, keep what pays:

1. **`-Osize` for the web release** (−1.8 MB, free). A `swiftSettings`
   entry under `STARLING_WASM`, release only.
2. **The regex** (−1.2 MB): `Print.swift`'s one literal
   (`/^ *(?:[-+*] |[0-9]+[.):] )?/`, the debugPrint indentation) becomes
   ten lines of `Character` tests. Also removes the reason the `Flutter`
   target needs `BareSlashRegexLiterals`.
3. **`FoundationEssentials`, 3.6 MB**: `--why-extract` per member to see
   which of Date, JSON, UUID, Data, `AttributedString`, Predicate is
   pulled and by whom. `AttributedString` and Predicate are large and
   probably reached by accident; each accidental one is a call site to
   change.
4. **Cross-module dead stripping.** `-Xswiftc -lto=llvm-full` with
   `-Xswiftc -internalize-at-link` lets the linker drop framework code the
   app never calls — the 3.8 MB of `Flutter` is every widget, and
   CounterApp uses a dozen. Measure the link time (LTO on 100k functions
   may cost minutes); if it is bearable it is the largest single lever
   after ICU. Decide after measuring, not before.
5. **`wasm-opt -Oz`** (binaryen, `brew install binaryen`) as a post-link
   pass in `web-app.sh` when present; typically 10–15% on Swift output.
6. **CupertinoIcons** (0.4 MB): 1,322 `static let` with metadata each; a
   table of `(name, codepoint)` would be a tenth of it. Only if the rest
   has not reached the target.

## Phase 3 — serving (½ day)

- `web-app.sh` writes `app.wasm.br` beside `app.wasm` (`brotli -9`), and the
  dev server sends it with `Content-Encoding: br` when the browser accepts
  it. `--serve` needs a small Python handler instead of `http.server`.
- `index.html` gets a loading indicator that shows fetch progress: at any
  size, a blank page for two seconds looks broken.

## Not on this list

- **Embedded Swift**: would remove the stdlib's metadata and most of the
  runtime, but has no Foundation and no existentials, and the framework is
  built on both. Not a path.
- **Splitting the framework into a separately cached module**: browsers
  cache `app.wasm` already; a split only helps once several apps share one
  origin, which is not the case yet.
- **Trimming `FoundationEssentials` by rebuilding it**: building the
  toolchain's Foundation ourselves is a project, not a step.

## Risks

- `String(format:)` behaviour: the shim must match for the specifiers in
  use, in particular `%.1f` rounding and `%d` on `Int64`. One test file with
  the audited strings, run natively against Foundation's, settles it.
- Shadowing imported names (`Timer`, `RunLoop`, `NSLock`, `FileHandle`,
  `String(format:)`) is a trick that works while all uses are in the
  `Flutter` module. A use in an app target sees Foundation's again — and
  links its ICU. The phase-0 check catches that; the app-facing fix, if it
  comes to it, is `@_exported` from the bridge module as `DispatchQueue` is.
- LTO may not be reliable on this toolchain for a module this size. It is
  measured, not assumed, and phase 2 lands without it if it fails.
