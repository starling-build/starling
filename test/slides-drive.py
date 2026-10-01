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
        d.click(124, 123); d.click(160, 189)         # back to Widescreen for the steps after

    if step("textbox"):
        d.click(156, 90); d.click(217, 140)
        d.key(text="A text box")
        d.shot("textbox", "Insert → Text Box: a box in the middle with the text, accent outline")

    if step("shapes"):
        # A blank slide of its own, from the Home tab.
        d.click(96, 90); d.click(1250, 700)
        d.click(207, 140)
        d.click(300, 125); d.click(280, 329)          # Layout → Blank
        d.click(156, 90); d.click(289, 140)           # Insert → Shapes
        d.shot("shapes-menu", "The Shapes gallery menu: Rectangle … Callout")
        d.click(270, 223)                            # Rounded Rectangle
        d.shot("shape-inserted", "A blue rounded rectangle, centred, selected with 8 handles and a rotation handle")
        d.drag(826, 498, 600, 360)
        d.shot("shape-moved", "The shape moved up-left; still selected")
        d.click(1250, 700)
        d.shot("deselected", "Clicked bare slide: no selection")
        d.click(600, 360)
        d.drag(671, 413, 760, 470)                   # its bottom-right handle
        d.shot("shape-resized", "Bottom-right handle dragged: the shape grew, top-left stayed")
        d.click(156, 90); d.click(289, 140); d.click(270, 195)   # Rectangle
        d.drag(826, 498, 826, 260)
        d.shot("guides", "A second shape dragged up: a red guide shows while aligned (may be gone after release)")
        d.click(96, 90)                              # Home
        d.shot("home-drawing", "Home tab: Drawing group with Shapes, Arrange, fill and outline colours")
        d.key(key=KEY["delete"])
        d.shot("deleted", "The selected rectangle deleted")
        d.key(text="z", mods=("command",))
        d.shot("undo-delete", "⌘Z: the rectangle is back")
        d.click(826, 260); d.click(826, 260)
        d.key(text="Hello")
        d.shot("shape-text", "Second click on a selected shape types into it: white centred text, dashed frame")
        d.key(key=KEY["escape"])
        d.shot("escape", "Esc: text kept, shape selected with a solid frame")
        d.drag(450, 250, 1300, 720)
        d.shot("marquee", "Marquee: the rounded rectangle (wholly inside) selected; the one over the top edge is not")
        d.click(645, 388)
        d.drag(645, 285, 790, 300)
        d.shot("rotated", "Rotation handle dragged: the rounded rectangle turned about 60°, handles turned with it")
        d.key(text="z", mods=("command",))
        d.shot("unrotated", "⌘Z: square again")

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
