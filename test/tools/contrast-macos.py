#!/usr/bin/env python3
"""WCAG AA check of the macOS-style shell tokens (literals in DesktopTheme.swift). Text 4.5:1, icons 3:1."""
import re, sys
src = open(sys.argv[1] if len(sys.argv) > 1 else "shell/Sources/DesktopShellApp/Utils/DesktopTheme.swift").read()
def lum(c):
    f = lambda v: v/12.92 if v <= .03928 else ((v+.055)/1.055)**2.4
    return .2126*f(c[0]/255)+.7152*f(c[1]/255)+.0722*f(c[2]/255)
def over(fg, bg):
    a = fg[3]/255
    return tuple(fg[i]*a+bg[i]*(1-a) for i in range(3))
def ratio(fg, bg):
    l1, l2 = lum(over(fg, bg)), lum(bg)
    return (max(l1, l2)+.05)/(min(l1, l2)+.05)
def theme(name):
    body = src[src.index(f"static let {name} = ShellTheme("):]
    body = body[:body.index("\n    )")]
    d = {}
    for k, v in re.findall(r"(\w+): Color\(0x([0-9A-Fa-f]{8})\)", body):
        n = int(v, 16); d[k] = ((n >> 16) & 255, (n >> 8) & 255, n & 255, n >> 24)
    return d
bad = 0
for name in ("macosDark", "macosLight"):
    t = theme(name)
    # chrome surfaces are drawn over an unknown wallpaper: check over the solid bar fill, and over black and white as extremes of the blur
    for bgname, bg in (("barFill", t["barFill"][:3]), ("panelFill", over(t["panelFill"], t["barFill"][:3])), ("controlFill", t["controlFill"][:3])):
        for fg, want in (("fgPrimary", 4.5), ("fgSecondary", 4.5), ("fgTertiary", 4.5), ("dockLabelText", 4.5)):
            if fg == "dockLabelText": b = over(t["dockLabelTint"], t["barFill"][:3])
            else: b = bg
            r = ratio(t[fg], b)
            flag = "FAIL" if r < want else "ok"
            if r < want: bad += 1
            print(f"{name:10} {fg:13} on {bgname:11} {r:5.2f} (need {want}) {flag}")
    r = ratio(t["accentInk"], t["accent"][:3]); print(f"{name:10} accentInk on accent {r:5.2f} (need 4.5) {'FAIL' if r<4.5 else 'ok'}"); bad += r < 4.5
    r = ratio(t["accent"], t["barFill"][:3]); print(f"{name:10} accent (icon) on bar {r:5.2f} (need 3) {'FAIL' if r<3 else 'ok'}"); bad += r < 3
sys.exit(1 if bad else 0)
