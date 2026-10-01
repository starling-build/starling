#!/usr/bin/env python3
"""Drive Sheets on macOS through its milestone checklist; screenshot each step.

    test/sheets-drive.py [--out DIR] [--only STEP,...]

The Sheets twin of test/slides-drive.py, built on office-drive.py's
Driver: it launches OfficeApp --sheets (OFFICE_APP overrides the binary,
default apps/OfficeApp/.build/debug/OfficeApp), touches only the instance
it started, and writes DIR/<nn>-<step>.png plus DIR/index.md listing what
each picture should show. Read the pictures; the script cannot judge them.
Coordinates are window-relative points at the default 1440x932 window.
"""
import argparse, importlib.util, os, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("office_drive", os.path.join(HERE, "office-drive.py"))
od = importlib.util.module_from_spec(spec)
spec.loader.exec_module(od)
if os.environ.get("OFFICE_APP"):
    od.APP = os.environ["OFFICE_APP"]
KEY = od.KEY

# Grid geometry at 100%: the first column starts after the row header
# (40 px), the first row under the column header (20 px); cells are 64x20.
GRID_X, GRID_Y = 0, 268   # the column header's top edge, measured from the "blank" shot

def cell(col, row):
    """Window point at the centre of a cell (zero-based)."""
    return GRID_X + 40 + col * 64 + 32, GRID_Y + 20 + row * 20 + 10

def run(d, only):
    def step(name):
        return not only or name in only

    # Another app's window can come to the front between steps (the Driver
    # re-fronts ours before input, not before a picture): re-front it here.
    shot = d.shot
    def guarded_shot(*a, **k):
        d._guard(); time.sleep(0.3); shot(*a, **k)
    d.shot = guarded_shot

    d.launch(args=["--sheets"])
    d.shot("blank", "Book1 — Sheets: ribbon (Home Insert Formulas Data Review View), formula bar, empty grid A1 selected, Sheet1 tab")

    if step("type"):
        d.click(*cell(0, 0))
        for t in ["Item", "Apples", "Pears", "Plums", "Total"]:
            d.key(text=t); d.key(key=KEY["enter"])
        d.click(*cell(1, 0))
        for t in ["Price", "1.2", "0.85", "2.5"]:
            d.key(text=t); d.key(key=KEY["enter"])
        d.click(*cell(2, 0))
        for t in ["Qty", "10", "24", "6"]:
            d.key(text=t); d.key(key=KEY["enter"])
        d.shot("typed", "Labels left-aligned, numbers right-aligned; the active cell moved down after each Enter")

    if step("formula"):
        d.click(*cell(3, 0)); d.key(text="Cost"); d.key(key=KEY["enter"])
        d.key(text="=B2*C2"); d.key(key=KEY["enter"])
        d.key(text="=B3*C3"); d.key(key=KEY["enter"])
        d.key(text="=B4*C4"); d.key(key=KEY["enter"])
        d.key(text="=SUM(D2:D4")
        d.shot("editing", "In-cell editor shows =SUM(D2:D4 with a caret; formula bar mirrors it; status says Enter")
        d.key(key=KEY["enter"])
        d.click(*cell(3, 4))
        d.shot("total", "D2:D4 = 12, 20.4, 15; D5 = 47.4; formula bar shows =SUM(D2:D4) (the paren closed)")

    if step("recalc"):
        d.click(*cell(2, 1)); d.key(text="20"); d.key(key=KEY["enter"])
        d.shot("recalc", "C2 = 20: D2 = 24 and the total D5 = 59.4")

    if step("select"):
        d.drag(*cell(1, 1), *cell(3, 3))
        d.shot("range", "B2:D4 tinted with a border, B2 white; status bar: Average 8.9…, Count 9, Sum 80.…")

    if step("format"):
        d.drag(*cell(0, 0), *cell(3, 0))
        d.key(text="b", mods=("command",))
        d.drag(*cell(3, 1), *cell(3, 4))
        d.click(*cell(5, 10))
        d.shot("bold", "Row 1 headers bold")

    if step("tabs"):
        d.click(87, 884)
        d.shot("tab-plus", "A second sheet (Sheet2) added and active; the grid is empty")

    print("done")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=None)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    out = a.out or tempfile.mkdtemp(prefix="sheets-drive-")
    os.makedirs(out, exist_ok=True)
    d = od.Driver(out)
    try:
        run(d, set(filter(None, a.only.split(","))))
    finally:
        d.quit()
        with open(os.path.join(out, "index.md"), "w") as f:
            for name, expect, alive in d.index:
                f.write(f"- `{name}` — {expect}{'' if alive else ' **(app had exited)**'}\n")
    print(out)

if __name__ == "__main__":
    main()
