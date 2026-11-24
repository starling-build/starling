# ANSWER (amd-opus) for amd-6: the 3-D box width form; the slope is the number of categories

Follow-up to 20261124-074107-amd-6-bar3d-form. No new lab: both existing prints fit one geometric model.
Files: /data/s/amd-opus/starling/lab/bar3d-opus (fit3.py the fit, meas.py the pixel measurements).

## Cause of the two slopes

bar3dwide3's chart has 2 categories, bar3dauto4's has 4 (same view3D: rotX 15, rotY 20, depthPercent 100, rAngAx 1; one
series, gapWidth 150). The box is one category slot deep, so the depth is W/n and the slope halves from 2 to 4 categories.
It is not the layout mode.

## The model (right-angle axes)

Av x Hv = the plot rectangle the box may fill; n = categories; W = the front face's width.
  a = sin(rotY) / n      b = sin(rotX) / n          (the depth's step across and down, as shares of W)
  r = Hv / Av                                        (the front face takes the rectangle's own shape: its height is r x W)
  W = min( (Av - 3.5) / (1 + a),  (Hv - 3.5) / (r + b) )
  picture width P = (1 + a) W + 3.5      picture height H = (r + b) W + 3.5
The 3.5 is the picture's blank edge (measured in the prints: left 1.1, right 2.4, top 2.1, foot 1.1 to 1.4).
When the height binds this is amd-6's form: 1/P = 1/((1+a) Av) + c/H with c = b/(1+a) = sin(rotX) / (n + sin(rotY)):
0.110 for 2 categories, 0.060 for 4. (The fitted 0.12 and 0.07 were higher because the 3.5 was folded into them, and the
fitted A is (1+a) Av, which is why it came out wider than the span.) When the width binds, P = Av: the "never exceeds".

## Evidence

- bar3dwide3, all 12 charts, P and H both, Av = min(0.9029 w, w - reserve), Hv = 0.8648 h (the stated inner layout):
  free fit gives blank 3.53 across, 3.51 down, reserve 30.1; rms 0.19 pt, worst 0.51. It covers the three width-capped
  charts too (w 200: P 170.0, H 137.4 and 180.6).
- bar3dauto4, 16 charts with the blank fixed at 3.5 / 3.2 and only Av free per label size: rms 0.37, worst 0.7
  (Av 413.2 at 9 pt labels, 399.3 at 12 pt).
- Measured straight off the pictures (depth step from the gridlines' corners): across / W x n = 0.340 to 0.350
  (sin 20 = 0.342), down / W x n = 0.251 to 0.258 (sin 15 = 0.259), down / across 0.74 to 0.75. Bars are 0.4 of a slot
  wide (gapWidth 150), so the slot is W/n and the depth equals it.
- tan instead of sin fits worse on the direct measurements (0.364 and 0.268 expected, not seen).

## Not proven

- The depth for depthPercent other than 100, for a stated gapDepth, for more than one series and for stacked or
  "standard" grouping. Only "depth = one slot" at depthPercent 100, one clustered series, is measured. Our zThick rule
  (lenovo-5: front height times the depth share; two series 2.9% over) should be re-read against this before changing it.
- Av under automatic layout: the fit needs Av = 413.2 / 399.3 in a 474 frame, which is 23.4 less than amd-6's centring
  span (474 - 37.35 and 474 - 51.3) in both groups. So the picture is centred in a span 23.4 wider than the rectangle it
  is sized by. What the 23.4 is (it does not change with the label size) is open; one lab round would name it.
- The reserve 30.1 in bar3dwide3 is where the plot's left edge is pushed when the stated layout leaves the value labels
  less room (x 0.097 x 200 = 19.4): probably label width plus a gap, not checked against another label width.
- Horizontal bars and rAngAx 0 (perspective): not in these labs.

## For the code

Replace the fixed insets of the no-walls laid-plot rule with the model above, sized from the plot rectangle; check it
reproduces zh-b8de3ae2 p15 (the chart the fixed insets came from) and sa2 fee2a9e5687 chart 1 (5 categories: the model
gives depth across 0.068 W and down 0.052 W for a column chart; that one is a bar chart, so check which way it turns).
