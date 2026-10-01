#!/usr/bin/env python3
"""Drive Slides on macOS through its milestone checklist; screenshot each step.

    test/slides-drive.py [--out DIR] [--only STEP,...]

The Slides twin of test/office-drive.py, and built on its Driver: it
launches apps/OfficeApp/.build/debug/OfficeApp --slides, touches only the
instance it started, and writes DIR/<nn>-<step>.png plus DIR/index.md
listing what each picture should show. Read the pictures; the script
cannot judge them. Coordinates are window-relative points at the default
1440x932 window. The same driver limit applies: a modifier held across a
synthetic click never reaches the app, so Shift-click is checked by hand.
"""
import argparse, importlib.util, os, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("office_drive", os.path.join(HERE, "office-drive.py"))
od = importlib.util.module_from_spec(spec)
spec.loader.exec_module(od)
KEY = od.KEY

def run(d, only):
    def step(name):
        return not only or name in only

    d.launch(args=["--slides"])
    d.shot("blank", "Presentation1 — Slides: one title slide, prompts in both placeholders, notes pane")

    if step("text"):
        d.click(826, 450); d.key(text="Quarterly review")
        d.shot("title", "Title typed at 60 pt, bottom-anchored; the Font box shows 60; thumbnail follows")
        d.click(826, 560); d.key(text="Starling team, October 2026")
        d.shot("subtitle", "Subtitle typed, centred, 24 pt")
        d.click(600, 840); d.key(text="Mention the perf gate.")
        d.shot("notes", "Notes typed in the notes pane")
        d.click(1380, 700)
        d.shot("deselect", "Editing ended: no outline on the filled placeholders, text stays")

    if step("slides"):
        d.click(207, 140)
        d.shot("new-slide", "Slide 2, Title and Content: bullet prompt after the bullet")
        d.click(826, 310); d.key(text="What shipped")
        d.click(700, 500); d.key(text="Writer opens and saves docx"); d.key(key=KEY["enter"])
        d.key(text="Slides starts today"); d.key(key=KEY["enter"]); d.key(text="Engine debt paid")
        d.shot("bullets", "Title and three bullets; thumbnail 2 shows them")
        d.click(300, 125)
        d.shot("layout-menu", "Layout menu, Title and Content checked")
        d.click(300, 217)
        d.shot("section-header", "Layout → Section Header: title moves to the lower half, bullets kept below it")
        d.click(1380, 700)
        d.key(key=KEY["up"])
        d.shot("key-up", "Up arrow with nothing being edited: slide 1 selected")
        d.key(key=KEY["down"])
        d.shot("key-down", "Down arrow: back on slide 2")

    if step("design"):
        d.click(219, 90); d.click(124, 123)
        d.shot("size-menu", "Design → Slide Size menu, Widescreen checked")
        d.click(160, 161)
        d.shot("four-three", "Standard 4:3: slide and thumbnails narrower, text re-laid")

    if step("textbox"):
        d.click(156, 90); d.click(217, 140)
        d.key(text="A text box")
        d.shot("textbox", "Insert → Text Box: a box in the middle with the text, accent outline")

    if step("switch"):
        d.click(33, 86); d.shot("backstage", "Backstage home: Blank document, Blank presentation, Open")
        d.click(315, 210)
        d.shot("to-writer", "Blank document: the window is Writer, Document1 — Writer")

    d.shot("final", "Still running, no crash dialog")
    with open(os.path.join(d.out, "index.md"), "w") as f:
        f.write("| picture | should show | app alive |\n| --- | --- | --- |\n")
        for name, expect, alive in d.index:
            f.write(f"| {name} | {expect} | {'yes' if alive else 'NO'} |\n")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "slides-drive"))
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    if not os.path.exists(od.APP):
        sys.exit("build the app first: swift build --package-path apps/OfficeApp")
    d = od.Driver(a.out)
    try:
        run(d, set(filter(None, a.only.split(","))))
    finally:
        d.quit()
    print("wrote", len(d.index), "pictures to", a.out, "- read index.md, then the pictures")
