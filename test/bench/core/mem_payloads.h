/* Payload generators shared by bench_mem.c (our core alone) and bench_mem_vs.c
 * (ours against libghostty-vt).
 *
 * They live in a header, included by both, for one reason: a memory comparison
 * is only a comparison if both engines are handed the SAME BYTES. Two copies of
 * "roughly the same generator" drift — one emits a trailing reset, one does
 * not, one fills 80 columns of CJK where the other fills 40 — and every drift
 * lands directly on the number being compared, in a way no assertion catches.
 *
 * Each builder writes ONE line of exactly `cols` COLUMNS and returns bytes
 * written. Columns, not bytes, is the invariant: a styled line is ~30x the
 * bytes of a plain one and a CJK line is half the characters, but all three
 * must fill the same grid or the payloads measure different amounts of screen.
 *
 * Callers append CRLF themselves — see the ONLCR note in bench_mem.c.
 */
#ifndef MEM_PAYLOADS_H
#define MEM_PAYLOADS_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int mp_utf8(char *out, uint32_t cp) {
    if (cp < 0x80) { out[0] = (char)cp; return 1; }
    if (cp < 0x800) {
        out[0] = (char)(0xC0 | (cp >> 6));
        out[1] = (char)(0x80 | (cp & 0x3F));
        return 2;
    }
    if (cp < 0x10000) {
        out[0] = (char)(0xE0 | (cp >> 12));
        out[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
        out[2] = (char)(0x80 | (cp & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (cp >> 18));
    out[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    out[3] = (char)(0x80 | (cp & 0x3F));
    return 4;
}

static int mp_line_plain(char *out, int cols, long n) {
    int o = 0;
    for (int i = 0; i < cols; i++) out[o++] = (char)('A' + (int)((n + i) % 26));
    return o;
}

/* Wide CJK, two columns each, plus one ZWJ emoji cluster every 8th line. The
   cluster is the point: it is the only content that grows a grapheme store,
   which both engines keep outside the cells. */
static int mp_line_unicode(char *out, int cols, long n) {
    int o = 0, col = 0;
    if (n % 8 == 0 && cols >= 4) {
        o += mp_utf8(out + o, 0x1F468);   /* man + ZWJ + woman + ZWJ + girl */
        o += mp_utf8(out + o, 0x200D);
        o += mp_utf8(out + o, 0x1F469);
        o += mp_utf8(out + o, 0x200D);
        o += mp_utf8(out + o, 0x1F467);
        col += 2;
        o += mp_utf8(out + o, 0x1F1EF);   /* regional indicator pair -> flag */
        o += mp_utf8(out + o, 0x1F1F5);
        col += 2;
    }
    while (col + 2 <= cols) {
        o += mp_utf8(out + o, 0x4E00 + (uint32_t)((n * 31 + col) % 0x3000));
        col += 2;
    }
    while (col < cols) { out[o++] = ' '; col++; }
    return o;
}

/* A distinct truecolor fg and 256-colour bg per cell. For a core that interns
   styles per page this grows the style table; for one that stores fg/bg/attrs
   inline in every cell it must cost exactly what plain costs. The divergence
   between those two answers is the most interesting column in the table. */
static int mp_line_styled(char *out, int cols, long n) {
    int o = 0;
    for (int i = 0; i < cols; i++) {
        long k = n * 7 + i;
        o += sprintf(out + o, "\033[38;2;%ld;%ld;%ldm\033[48;5;%ldm%c",
                     (k * 7) % 256, (k * 13) % 256, (k * 29) % 256,
                     16 + (k % 216), (char)('A' + (int)(k % 26)));
    }
    o += sprintf(out + o, "\033[0m");
    return o;
}

static int mp_line_mixed(char *out, int cols, long n) {
    switch (n % 3) {
        case 0: return mp_line_plain(out, cols, n);
        case 1: return mp_line_unicode(out, cols, n);
        default: return mp_line_styled(out, cols, n);
    }
}

typedef int (*MpLineFn)(char *, int, long);

/* Resolves a payload name. `*lines` and `*trailing_newline` are only written
   for the payloads that override them: `empty` feeds nothing, and `screen`
   fills the visible grid and withholds the final CRLF so nothing scrolls —
   that is the cost of a full screen, not of a screen plus a row of history. */
static MpLineFn mp_resolve(const char *name, int rows, long *lines,
                           int *trailing_newline) {
    if (!strcmp(name, "empty"))   { *lines = 0; return NULL; }
    if (!strcmp(name, "screen"))  { *lines = rows; *trailing_newline = 0; return mp_line_plain; }
    if (!strcmp(name, "plain"))   return mp_line_plain;
    if (!strcmp(name, "unicode")) return mp_line_unicode;
    if (!strcmp(name, "styled"))  return mp_line_styled;
    if (!strcmp(name, "mixed"))   return mp_line_mixed;
    return NULL;
}

/* Worst case is the styled line: ~31 bytes per cell plus a reset and CRLF. */
#define MP_LINE_CAP(cols) ((size_t)(cols) * 40 + 128)
#define MP_FEED_CHUNK 65536

#endif
