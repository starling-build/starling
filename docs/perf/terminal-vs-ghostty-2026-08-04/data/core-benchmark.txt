offline emulator core, 59.7MB DOOM-Fire stream @47x201, no rendering:
  swift -O                                122 MB/s   cellwrites 3811720
  swift -O -enforce-exclusivity=unchecked 180 MB/s   cellwrites 3811720
  swift -Ounchecked + exclusivity off     240 MB/s   cellwrites 3811720
  c++ -O2                                 660 MB/s   cellwrites 3811774
swift core profile (no rendering): exclusivity 33.3%, ARC 7.4%, COW 6.1% = 46.8% runtime overhead; 43.2% emulator work

C vs C++ core (same streams, same cell-write counts, same checksums):
  doomstream (SGR)   C 680 MB/s   C++ 670 MB/s   swift 122 MB/s
  doomstream_nosgr   C 1124       C++ 1038       swift 136
  doomstream_ascii   C 595        C++ 604        swift 110
swift TermCell: size 13, stride 16, align 4, offsets 0/4/8/12; CellAttrs.rawValue is UInt8
matching C struct: { uint32_t scalar, fg, bg; uint8_t attrs; } == 16 bytes, attrs at 12

render-ceiling check (59.7MB doomstream.bin, ours @56x244, ghostty @45x201):
  live normal            0.646s  1.32 cpu   92 MB/s
  live repaints off      0.594s  0.59 cpu  100 MB/s   (STARLING_TERM_MIN_REPAINT=1000)
  offline core alone     0.510s        --  117 MB/s
  ghostty nightly live   0.384s  0.81 cpu  155 MB/s
=> rendering = 0.73 CPU-s but only 0.052s wall (93% parallel, 8% of critical path)
=> critical path is 79% emulator core; core speedups translate nearly 1:1
=> projected: swift 2x restructure -> 0.39s/153 MB/s (parity); C core 5.6x -> 0.23s/263 MB/s

=== C CORE (Sources/CStarlingTerm) — suite at 47x201 on GNOME vs ghostty nightly ===
  ours 2.618s wall / 3.72 CPU-s   ghostty-nightly 3.998s / 7.19   => 0.65x wall, 0.52x CPU
  (was, with the Swift core: 4.535s / 7.39 = 1.13x wall, 1.03x CPU — a loss)
  live doomstream, Starling session: 92 -> 250 MB/s, cpu 1.32 -> 0.48 CPU-s
  emulator core alone: 1.1x-5.1x faster per workload (unicode 5.1x, sgr_fg 4.2x)
  RSS still climbs (276/335/386) => the leak is NOT in the emulator
