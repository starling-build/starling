# lenovo-5 HANDOFF: slide 3-D bar value labels (PR 1734)
- Lab lab-bar3d-series2 (24 charts): the label's left edge is 6.3 pt past the front face's right end, whatever depth, gap depth or series count. Rule changed from "centred in the side face".
- Result: gap depth 150 charts within 1 pt of PowerPoint (p10, p12, p24); LIBRE_OFFICE-100610 p2..p10 labels within about 1 pt.
- OPEN: gap depth 0 charts. PowerPoint's front right end is the same (830) for n=1 dp100 and n=2 dp200; ours moves with depth (p14 775, p1 837, p18 off by 19 pt). The axis-width rule (slide-3d-bars-share-the-laid-plot...) is not fitted for gap depth 0 or one series. Next: tabulate front right edge for all 24 pages against our axis rule.
