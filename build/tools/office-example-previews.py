#!/usr/bin/env python3
"""Render the landing previews with Office's own painters, not a mock renderer.

Use the environment from office-examples-requirements.txt. Exported PDFs are
private temporary intermediates; only the three preview PNGs enter the website.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile
import pymupdf

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    "--office-app", type=Path, default=ROOT / "apps/OfficeApp/.build/release/OfficeApp"
)
parser.add_argument("--examples", type=Path, default=ROOT / "web/office/examples")
parser.add_argument("--output", type=Path, default=ROOT / "ui/openoffice/images")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="office-example-previews-") as directory:
    for app, name, mode, pages in [
        ("writer", "garden-brief.docx", "--convert", 3),
        ("slides", "garden-presentation.pptx", "--deck-pdf", 9),
        ("sheets", "garden-budget.xlsx", "--sheet-pdf", 5),
    ]:
        pdf = Path(directory) / f"{app}.pdf"
        subprocess.run(
            [str(args.office_app), mode, str(args.examples / name), str(pdf)],
            check=True,
            timeout=120,
        )
        with pymupdf.open(pdf) as document:
            if len(document) != pages:
                raise ValueError(f"{app}: expected {pages} pages, got {len(document)}")
            page = document[0]
            clip = page.rect
            if app == "sheets":
                # The first printed sheet fits on one landscape page. Crop only
                # its blank lower half and print footer for a legible preview.
                clip = pymupdf.Rect(
                    18, 30, page.rect.width - 18, page.rect.height * 0.62
                )
            scale = (918 if app == "writer" else 1440) / clip.width
            image = page.get_pixmap(
                matrix=pymupdf.Matrix(scale, scale), clip=clip, alpha=False
            )
            path = args.output / f"{app}-sample.png"
            image.save(path)
            print(f"{path}: {image.width}x{image.height}")
