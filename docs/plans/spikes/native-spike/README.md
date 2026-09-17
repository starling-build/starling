# native-spike

The calibration spike for `docs/plans/native-framework.md` ("Spike results").
macOS only. Build and run:

    swift run

It opens a window, commits a retained node tree to CALayers, starts one
compositor-owned spring (blue) with a shadow spring and one in-process
spring (orange), retargets the blue one at 0.25 s, sleeps the main thread
for 2 s at 0.5 s, and prints per-tick shadow-vs-presentation deltas and
commit timings to stdout. Screenshot it from another process during the
sleep to see the blue ball still moving.
