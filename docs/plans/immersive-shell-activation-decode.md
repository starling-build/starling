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

On the Windows build box (`starling@192.168.68.60`), all tooling already
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
