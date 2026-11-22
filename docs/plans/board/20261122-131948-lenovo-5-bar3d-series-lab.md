# lenovo-5: slide 3-D bars, front height by series count (lab bar3d-series, round 1: LANDED)

Lab: 24 prints (1-6 series, gapDepth 0/150, depthPercent 100/200, plot 222.1 pt). The image is the whole box (222.1 pt always); inside it the bars sit with their top face 3.2 pt under the top and the front 2-3 pt over the bottom.
Rule found: 222.06 = pad + n*h + (1+gapDepth)*depth*0.25*h, h = one series' front height, 0.25 = sin(rotX)*cos(rotX) at rotX 15. Fits all 24 within 0.8 pt per front (the fit pad is 6.9; the lab's own pads are 5.4; real LIBRE_OFFICE p2-p10 want 4.4, so 2.7 top + 1.7 foot was used). Ours had used sin(rotX) and no pad: fronts 1.2 to 6.6 pt too tall for 1 to 6 series.
Result, LIBRE_OFFICE-100610-0 box height ours vs PowerPoint: 2 series 185.6/186.7, 3 series 195.0/195.1, 4 series 200.0/199.9 (was 203.5).
Left: plot height was 222.1 in every lab chart, so the pad's dependence on plot height is untested (round 2 if needed). n=1 not covered (horizontal axis rule excludes it).
