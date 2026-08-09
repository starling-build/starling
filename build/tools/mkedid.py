#!/usr/bin/env python3
"""Build a minimal valid EDID 1.3 for a 1920x1080@60 digital sink.

Used to force a headless DRM connector to expose a usable mode list, so the
compositor programs a real CRTC and scans out into memory with no monitor
attached.
"""
import sys

def detailed_timing(clk_khz, ha, hb, hfp, hsync, va, vb, vfp, vsync, wmm, hmm):
    clk = clk_khz // 10
    d = bytearray(18)
    d[0] = clk & 0xFF
    d[1] = (clk >> 8) & 0xFF
    d[2] = ha & 0xFF
    d[3] = hb & 0xFF
    d[4] = ((ha >> 8) & 0x0F) << 4 | ((hb >> 8) & 0x0F)
    d[5] = va & 0xFF
    d[6] = vb & 0xFF
    d[7] = ((va >> 8) & 0x0F) << 4 | ((vb >> 8) & 0x0F)
    d[8] = hfp & 0xFF
    d[9] = hsync & 0xFF
    d[10] = ((vfp & 0x0F) << 4) | (vsync & 0x0F)
    d[11] = (((hfp >> 8) & 3) << 6 | ((hsync >> 8) & 3) << 4 |
             ((vfp >> 4) & 3) << 2 | ((vsync >> 4) & 3))
    d[12] = wmm & 0xFF
    d[13] = hmm & 0xFF
    d[14] = ((wmm >> 8) & 0x0F) << 4 | ((hmm >> 8) & 0x0F)
    d[15] = 0
    d[16] = 0
    d[17] = 0x1E          # digital separate sync, HSync+, VSync+
    return d

def descriptor(tag, payload):
    d = bytearray(18)
    d[0] = 0x00; d[1] = 0x00; d[2] = 0x00
    d[3] = tag
    d[4] = 0x00
    d[5:5 + len(payload)] = payload
    for i in range(5 + len(payload), 18):
        d[i] = 0x20 if tag in (0xFC, 0xFE, 0xFF) else 0x00
    return d

e = bytearray(128)
e[0:8] = bytes([0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00])
mfg = (12 << 10) | (14 << 5) | 24            # "LNX"
e[8] = (mfg >> 8) & 0xFF
e[9] = mfg & 0xFF
e[10] = 0x01; e[11] = 0x00                    # product code
e[12:16] = (1).to_bytes(4, "little")          # serial
e[16] = 1                                     # week
e[17] = 2026 - 1990                           # year
e[18] = 1; e[19] = 3                          # EDID 1.3
e[20] = 0x80                                  # digital input
e[21] = 51; e[22] = 29                        # cm
e[23] = 120                                   # gamma 2.2
e[24] = 0x0A                                  # RGB, preferred timing
# chromaticity (typical sRGB-ish)
e[25:35] = bytes([0xEE, 0x91, 0xA3, 0x54, 0x4C, 0x99, 0x26,
                  0x0F, 0x50, 0x54])
e[35] = 0x00; e[36] = 0x00; e[37] = 0x00      # established timings: none
for i in range(38, 54):                        # standard timings: unused
    e[i] = 0x01
# 1920x1080 @60: clk 148.5MHz, hblank 280 (fp 88, sync 44), vblank 45 (fp 4, sync 5)
e[54:72] = detailed_timing(148500, 1920, 280, 88, 44, 1080, 45, 4, 5, 509, 286)
e[72:90] = descriptor(0xFD, bytes([50, 75, 30, 160, 0x00, 0x0A,
                                   0x20, 0x20, 0x20, 0x20, 0x20, 0x20, 0x20]))
e[90:108] = descriptor(0xFC, b"Starling VD\x0a")
e[108:126] = descriptor(0x10, b"")
e[126] = 0                                     # no extensions
e[127] = (256 - (sum(e[0:127]) % 256)) % 256   # checksum

sys.stdout.buffer.write(bytes(e))
