# Decoding the ImmersiveShell activation dependency

**Question this answers:** CoreWindow-generation packaged apps (Settings,
Calculator, the old Store apps) refuse to launch unless explorer is running.
Prior work found explorer publishes an undocumented COM component the
activation asks for, and that "getting past its first method call only reveals
the next one." This note **decodes that surface** — how many interfaces, how
many methods, and their exact signatures — so we can judge whether Starling
can provide it instead of hosting explorer.

**Verdict up front:** the activation-broker surface is *small and fully
specified* — two interfaces, one method each, no branching tree. It is
implementable. But "provide it" means registering as the ImmersiveShell class
object (CLSID below), which exposes us to the rest of that class's contract,
not just these two methods — and the visible-window *frame* is a separate
dependency this note does **not** close. So this reduces the unknown to a
bounded, greenlightable build; it does not by itself replace explorer. The
hidden-explorer service (shipped, `b12ed96`) remains the reference
implementation and the right default today.

## The dependency chain (decoded)

Activation of a CoreWindow app reaches the **ImmersiveShell** object and asks
it, in order:

```
CoCreateInstance(CLSID_ImmersiveShell)          // C2F03A33-21F5-47FA-B4BB-156362A2F239
      -> QueryInterface(IID 848eaf0a-...)        // the "one service" prior work saw
      -> [848eaf0a]::Proc3(&obj)                 // getter: hand back the next object
      -> [a8ba8f26]::Proc3(long, long, str, enum, &enumOut)   // the actual work
```

That is the **entire** statically-reachable tree. `a8ba8f26::Proc3` takes only
scalars and a string and returns a scalar — it references no further COM
interface, so the chain terminates here. This is the concrete, quantified
version of "past its first method lies the next one": there is exactly *one*
next method, and it does not open further.

## Recovered signatures (MIDL-equivalent)

```idl
// Served by proxy CLSID {95E15D0A-66E6-93D9-C53C-76E6219D3341},
// implemented in twinui.dll (both IIDs live there, 0x30 apart).
// Neither interface has a registered friendly name.

[uuid(848eaf0a-4435-4d6f-bcdf-8f42ffb38400)]
interface IImmersiveShell_Svc : IUnknown {           // 1 method (slot 3)
    HRESULT Proc3([out] IUnknown_a8ba8f26** ppObject);   // FC_RP -> interface ptr
};

[uuid(a8ba8f26-1af0-4ffa-a75b-9d71de60ae80)]
interface IImmersiveShell_Activate : IUnknown {      // 1 method (slot 3)
    HRESULT Proc3(
        [in]  long     a,          // FC_LONG   - unknown scalar
        [in]  long     b,          // FC_LONG   - unknown scalar
        [in]  LPCWSTR  identity,   // FC_C_WSTRING - likely the AUMID / package identity
        [in]  int      flags,      // FC_ENUM32
        [out] int*     result);    // FC_ENUM32 - likely a result/cookie
};
```

Method names are placeholders (`Proc3` = first slot after IUnknown). NDR
format strings carry no names, and twinui.dll's public PDB is too thin to name
them (its `.rdata` resolves only to `DllCanUnloadNow+offset`). The parameter
*meanings* (marked "likely") are inference, not yet confirmed.

## How this was recovered (reproducible)

On the Windows build box (`starling@192.168.68.56`), all tooling already
present or fetched:

1. `HKCR\Interface\{848EAF0A-...}\ProxyStubClsid32` -> proxy CLSID
   `{95E15D0A-...}`; the interface key has no default (friendly) name.
2. OleViewDotNet v1.11 (`C:\dist\ole`), driven from PowerShell 5.1:
   `Get-ComDatabase -PassThru`, then `Get-ComProxy -Iid <iid>` returns the
   NDR-parsed procedures. Walking `procedure.Params[n].Type` through
   `NdrPointerTypeReference -> NdrInterfacePointerTypeReference` yields the
   `[out]` interface's IID — this is how `848eaf0a` was followed to
   `a8ba8f26`. `ptype.ps1` prints the FC base types above.
3. `scan.c` (compiled with the box's MSVC + DbgHelp) memory-scans the system
   DLLs for the two IID byte patterns and resolves nearest public symbols —
   located both IIDs in **twinui.dll** (adjacent), everything else clean.

Artifacts on the box: `C:\dist\iface-*.txt`, `C:\dist\ptype.ps1`,
`C:\dist\ndrmap.ps1`, `C:\dist\scan.c`. Microsoft's public symbol server
(`msdl.microsoft.com`) is reachable from the box.

## What is NOT yet closed

1. **Semantics of `a8ba8f26::Proc3`.** The two longs, the string, the in-enum
   and the out-enum are typed but not interpreted. Next step: a live trace of
   a working (explorer-present) Calculator activation, breakpointing the
   twinui.dll implementation to read real argument values — the string will
   likely reveal exactly what the call registers. Alternatively, disassemble
   twinui.dll around the `a8ba8f26` vtable.
2. **The visible-window frame is a separate dependency.** Our own testing
   (see `HANDOFF-winshell-minimize-and-packaged-apps.md`) showed apps can be
   *activated* yet come up as a bare, cloaked `Windows.UI.Core.CoreWindow`
   with no `ApplicationFrameWindow`. The frame is built by
   `ApplicationFrameHost.exe` under a director that this note has not mapped.
   Decoding the activation broker does not, on its own, produce a framed
   window.
3. **The full ImmersiveShell class contract.** Registering CLSID
   `C2F03A33` makes us *the* immersive shell component; Windows code beyond
   the activation path may QI our object for other interfaces and fail if we
   return `E_NOINTERFACE`. The two-interface finding is the activation slice,
   not the whole class. This is the open-ended risk the earlier session hit.

## Recommendation

Keep the hidden-explorer service as the default — it is the working reference
implementation and costs ~227 MB / 0.05% of a core. Treat this decode as the
foundation for a *future, optional* minimal-host experiment: a small object
that stands in as ImmersiveShell, answers the two decoded methods, and is
grown only as far as real activations demand — measured, not guessed. Before
committing to that build, close unknown #1 (a live trace, ~half a day) and
scope unknown #2 (the frame director), because #2 may be the larger of the
two and is entirely unmapped.

## How other Windows shells handle this (survey, 2026-08-25)

Short version: **nobody reimplements the immersive shell — everybody keeps
explorer, and so does Microsoft's own explorer-replacement.** Our hidden-
explorer service is the industry-standard answer, not a workaround.

- **Cairo Shell** (the most complete open-source desktop-environment /
  shell replacement; its ManagedShell library backs it). Setting Cairo as the
  Winlogon shell produces exactly our failure: "Class not registered" when
  launching UWP apps, and their own issues (#365, #936) call UWP + Settings a
  *blocker* for using Cairo as the primary shell. Their working configuration
  keeps Explorer as the shell. No reimplementation of the immersive shell.
- **RetroBar, Open-Shell, StartAllBack, ExplorerPatcher** — taskbar/Start
  replacements or explorer patches; explorer stays.
- **komorebi, GlazeWM** — tiling window managers; explorer stays.
- **Microsoft Shell Launcher v2 / `CustomShellHost.exe`** — the sanctioned
  "replace Explorer, still launch UWP (Settings, Touch Keyboard)" host for
  kiosk/embedded. Analyzed the binary directly on the box (it's on every
  install at `C:\Windows\System32\CustomShellHost.exe`; the web has no RE of
  it). Findings:
  - It imports the classic shell-registration APIs (`SetShellWindow`,
    `RegisterShellHookWindow`) and the WinRT activation APIs
    (`RoActivateInstance`), and has a function literally named
    `_ActivateApplicationForLaunchHelperWithWindowFactory` — it supplies a
    window factory for the launched app (the frame).
  - It references `CLSID_ImmersiveShell` and `IID_IServiceProvider`, and the
    disassembly shows all three sites are
    `CoCreateInstance(CLSID_ImmersiveShell, NULL,
    CLSCTX_LOCAL_SERVER|CLSCTX_ENABLE_CLOAKING, IID_IServiceProvider, &psp)`
    followed by `psp->QueryService` (vtable +0x18). It **consumes** the
    immersive shell via the documented `IServiceProvider`/`QueryService`
    pattern; it does **not** `CoRegisterClassObject` the ImmersiveShell CLSID.
  - So even Microsoft's minimal shell does not provide the immersive shell —
    it expects one to exist and asks it for services.

- **`CLSID_ImmersiveShell` has no standalone server.** Its registration is
  just `(default)=ImmersiveShell`, `AppID={316CDED5-...}` whose only value is
  `RunAs=Interactive User` — **no `LocalServer32`, no `InprocServer32`, no
  `DllSurrogate`.** COM cannot launch it; it exists only while some running
  process calls `CoRegisterClassObject(CLSID_ImmersiveShell)` at runtime. On a
  normal desktop that process is explorer.exe. There is nothing lighter to
  trigger.

**Consequence.** The immersive shell is intrinsically "whatever process is
being explorer." Providing it ourselves means registering
`CLSID_ImmersiveShell` and answering the full `IServiceProvider` service set
that activation + the frame factory pull — i.e. becoming explorer's immersive
hat, which is the open-ended contract, not the two internal methods decoded
above. The documented consumer pattern (what CustomShellHost uses) is
`IServiceProvider::QueryService`, not the `848eaf0a` route; the `848eaf0a`
pair is one internal consumer path and not the one to build against.

**Residual unknown:** under Shell Launcher v2, *which* process registers
`CLSID_ImmersiveShell` for CustomShellHost to consume (Shell Launcher may start
a background shell-experience host). Not resolved here — it needs the Enterprise
Shell Launcher feature enabled, which reconfigures logon and is too invasive
for the dev box. It does not change the conclusion: the provider is
explorer-class functionality, and keeping explorer (hidden) is what every
shell, including Microsoft's, effectively does.

## 2026-08-26 — the dependency has a *visible* failure, and it is a trade-off

Everything above is about whether a packaged app can be **activated** at all.
Keeping a hidden explorer solves that, and it does: on the box, activation
returns S_OK, the app process starts, and `ApplicationFrameHost` builds it a
frame. Measured this session, the shipped mainline build (`8f79405`) still
fails one step later, and the user sees it.

**The failure.** From a cold logon, every CoreWindow packaged app --
Settings and Calculator both, reproduced across four clean boots and two
binaries -- comes up with its `ApplicationFrameWindow` **DWM-cloaked by the
shell** (`DWMWA_CLOAKED` == 14 reads 2, `DWM_CLOAKED_SHELL`). The app runs, the
frame exists, every window API says it is visible, and nothing is ever
painted: *"Settings opens and shows nothing."* It does not clear on its own --
still cloaked six minutes in.

Note which window: a healthy launch has the app's own `Windows.UI.Core
.CoreWindow` cloaked (that is normal, and `app_window_up` in
`flwin32_explorer.c` says so) and its **frame** clear. Here the frame is
cloaked too. Reading the CoreWindow's cloak state answers the wrong question.

**The trade-off, which is the real finding.** Two cures were measured, and
they are mutually exclusive:

| what was restarted last | packaged-app frame | our desktop view |
|---|---|---|
| the explorer service | **uncloaked, visible** | **black, permanently** |
| the shell chrome | cloaked, invisible | wallpaper and icons fine |

Both directions were confirmed by pixel capture through `ddagrab` (GDI capture
is useless here -- it misses D3D-composited surfaces and will happily show a
wallpaper that is not on the screen). Restarting explorer with the session
settled took the desktop from mean luminance 117 to **0** on the same frame
that the packaged app became visible, and it stayed 0; restarting the chrome
afterwards brought 117 back and re-cloaked the app. So this is not an ordering
race to be papered over with a delay -- whichever of the two started last
wins, and the two prizes are on opposite ends.

That is the shape of a genuine conflict over the desktop slot: explorer's
desktop (Progman/WorkerW) and our own desktop view cannot both be the bottom
of the stack, and the immersive shell's frame-uncloaking appears to follow
whichever explorer instance owns it. It belongs with the decode above rather
than in the supervisor.

**Two fixes were written, tested, and reverted** -- recorded so nobody spends
the day again:
1. *Restart the explorer service when the supervisor respawns a crashed
   shell.* Premise disproved: a clean-boot test showed the bug with no crash
   anywhere, so the crash was not the trigger.
2. *Refresh the explorer service once, 180 s into the session.* It worked --
   verified twice from cold boot, cloak 2 -> 0 -- and blacked the desktop for
   the rest of the session. That is the same corrosion
   `flwin32_shell_ensure_explorer_service` already warns about, arriving from
   a new direction.

**The gate was blind to this, and now is not.** `test/win/gate.ps1` tested the
frame for blankness by grabbing its screen rectangle and counting distinct
colours -- but a cloaked window is painted by nobody, so the grab returns what
is *behind* it, which here is a photographic wallpaper. It scores a healthy
variety, and the check passed on a window the user could not see. The check now
asserts `DWMWA_CLOAKED == 0` directly, which is the only honest way to ask.

**What is NOT resolved: the discriminator.** With the assertion in, the gate
still passes -- and not because the assertion is broken. Instrumented, the
gate reads `cloak=0` on the frame it launches, in the same session, minutes
after a hand-driven `--launch-app` of the same app reads `cloak=2`. Both were
read the same two ways (by owning process, and by title+class the way the gate
finds it) and agreed with each other. So there are genuinely two states, and
what selects them is still unknown. Ruled out by measurement, each on the box:

- *a preceding crash* -- reproduced on clean boots with none;
- *how long the shell has been up* -- still cloaked at t+316 s;
- *the order or age of explorer vs the shell* -- fails at 4 s apart, fails at
  35 s and 60 s, works at 2 min and beyond, works with explorer 7 h older;
- *cold start vs resuming a suspended app* -- killed the app process first;
  identical either way;
- *whether the launching process owns the foreground* -- launched with and
  without a foreground window of our own; identical.

The gate's sequence does one thing the hand-driven probe does not: it opens
the file explorer view, creates and minimizes a real window, and takes the
foreground repeatedly before it ever launches a packaged app. Something in
that traffic puts the session into the state where frames uncloak. Finding
which is the next step, and it is worth doing from the gate's side --
bisecting *its* preceding checks -- rather than from the shell's, because the
gate is the reproducer that WORKS.

Until then, treat a gate PASS on the packaged-app check as "not reproduced",
not as "the user's apps are visible."
