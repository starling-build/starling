/* Conformance unit tests for the terminal's C emulator core: character
 * widths, grapheme clusters, joining rules, and the identity queries.
 * Every case here was first a live failure found by probing or by
 * ucs-detect; the suite pins the fixes at the cheapest possible tier —
 * plain C against starling_term.c, no Swift, no GPU, milliseconds.
 *
 * Built and run by test/run.sh ("unit tests: terminal core").
 */
#include "starling_term.h"
#include <stdio.h>
#include <string.h>

static int fails;

#define CHECK(cond, name) do { \
    if (cond) printf("  ok  %s\n", name); \
    else { printf("  FAIL %s (%s:%d)\n", name, __FILE__, __LINE__); fails++; } \
} while (0)

/* ---- response capture ---------------------------------------------------- */

static char resp_buf[512];
static size_t resp_len;
static void on_resp(void *ctx, const char *s) {
    (void)ctx;
    size_t n = strlen(s);
    if (resp_len + n < sizeof resp_buf) {
        memcpy(resp_buf + resp_len, s, n);
        resp_len += n;
    }
}
static void resp_clear(void) { resp_len = 0; resp_buf[0] = 0; }
static const char *resp(void) { resp_buf[resp_len] = 0; return resp_buf; }

/* ---- helpers ------------------------------------------------------------- */

static StarlingTerm *fresh(int cols, int rows) {
    StarlingTerm *t = starling_term_new(cols, rows);
    starling_term_set_response_cb(t, on_resp, NULL);
    resp_clear();
    return t;
}

static void feed(StarlingTerm *t, const char *s) {
    starling_term_feed(t, (const uint8_t *)s, strlen(s));
}

/* Cell at (row, col) of the live grid. */
static StarlingTermCell cell_at(StarlingTerm *t, int row, int col) {
    StarlingTermCell line[512];
    starling_term_copy_line(t, starling_term_scrollback_count(t) + row, line);
    return line[col];
}

static int cursor_col(StarlingTerm *t) { return starling_term_cursor_col(t); }

/* UTF-8 text of the cell at (row, col), NUL-terminated into buf. */
static const char *cell_text(StarlingTerm *t, int row, int col,
                             char *buf, int cap) {
    int n = starling_term_cell_text(t, cell_at(t, row, col).scalar, buf, cap - 1);
    buf[n < 0 ? 0 : n] = 0;
    return buf;
}

/* ---- width fundamentals -------------------------------------------------- */

static void test_widths(void) {
    printf("widths:\n");
    StarlingTerm *t = fresh(80, 24);
    feed(t, "a");
    CHECK(cursor_col(t) == 1, "ascii advances 1");
    feed(t, "\xe6\xb0\xb4");                     /* U+6C34 CJK water */
    CHECK(cursor_col(t) == 3, "CJK advances 2");
    feed(t, "\xe2\x8c\x9a");                     /* U+231A watch */
    CHECK(cursor_col(t) == 5, "U+231A advances 2 (ucs-detect's gate)");
    feed(t, "\xf0\x9f\x98\x80");                 /* U+1F600 emoji */
    CHECK(cursor_col(t) == 7, "emoji advances 2");
    CHECK(cell_at(t, 0, 1).attrs & STARLING_ATTR_WIDE, "CJK lead is WIDE");
    CHECK(cell_at(t, 0, 2).attrs & STARLING_ATTR_WIDE_CONT, "CJK cont marked");
    CHECK(cell_at(t, 0, 2).scalar == 0, "continuation carries scalar 0");
    starling_term_free(t);
}

static void test_wide_wrap_and_pairs(void) {
    printf("wide wrap and pair hygiene:\n");
    StarlingTerm *t = fresh(10, 4);
    feed(t, "123456789");                        /* cursor at last column */
    feed(t, "\xe6\xb0\xb4");                     /* wide can't fit in col 9 */
    CHECK(starling_term_cursor_row(t) == 1 && cursor_col(t) == 2,
          "wide char at margin wraps whole to next line");
    CHECK(cell_at(t, 1, 0).attrs & STARLING_ATTR_WIDE, "wrapped lead at col 0");
    /* Overwrite the continuation half: the lead must not survive alone. */
    feed(t, "\033[2;2H" "x");                    /* onto the cont cell */
    CHECK(cell_at(t, 1, 0).scalar == 32 && !(cell_at(t, 1, 0).attrs & STARLING_ATTR_WIDE),
          "overwriting the continuation blanks the lead");
    starling_term_free(t);
}

/* ---- variation selectors and flags -------------------------------------- */

static void test_vs_and_flags(void) {
    printf("variation selectors and flags:\n");
    char buf[64];
    StarlingTerm *t = fresh(80, 24);
    feed(t, "#\xef\xb8\x8f");                    /* '#' + VS16: keycap base */
    CHECK(cursor_col(t) == 2, "VS16 widens a narrow base");
    CHECK(strcmp(cell_text(t, 0, 0, buf, sizeof buf), "#\xef\xb8\x8f") == 0,
          "VS16 joins the cell's cluster");
    feed(t, "\r\n");
    feed(t, "\xe2\x8c\x9a\xef\xb8\x8e");         /* watch + VS15 */
    CHECK(cursor_col(t) == 1, "VS15 narrows a wide base");
    feed(t, "\r\n");
    feed(t, "\xf0\x9f\x87\xba\xf0\x9f\x87\xb8"); /* U+1F1FA U+1F1F8 flag US */
    CHECK(cursor_col(t) == 2, "an RI pair is one flag: two columns");
    CHECK(strcmp(cell_text(t, 2, 0, buf, sizeof buf),
                 "\xf0\x9f\x87\xba\xf0\x9f\x87\xb8") == 0,
          "both indicators live in the flag's cluster");
    feed(t, "\xf0\x9f\x87\xba\xf0\x9f\x87\xb8"); /* second flag */
    CHECK(cursor_col(t) == 4, "a second flag takes its own two columns");
    starling_term_free(t);
}

/* ---- grapheme clusters --------------------------------------------------- */

static void test_clusters(void) {
    printf("grapheme clusters:\n");
    char buf[96];
    StarlingTerm *t = fresh(80, 24);
    /* Family: man ZWJ woman ZWJ girl — one cell pair, full sequence kept. */
    feed(t, "\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7");
    CHECK(cursor_col(t) == 2, "ZWJ family occupies two columns");
    CHECK(strcmp(cell_text(t, 0, 0, buf, sizeof buf),
                 "\xf0\x9f\x91\xa8\xe2\x80\x8d\xf0\x9f\x91\xa9\xe2\x80\x8d\xf0\x9f\x91\xa7") == 0,
          "family cluster text preserved for the renderer");
    feed(t, "\r\n");
    /* Fitzpatrick: thumbs-up + type-1-2 melts into the base. */
    feed(t, "\xf0\x9f\x91\x8d\xf0\x9f\x8f\xbb");
    CHECK(cursor_col(t) == 2, "skin-tone modifier joins its base");
    feed(t, "\r\n");
    /* Malayalam conjunct: ka virama ka — capped at two columns. */
    feed(t, "\xe0\xb4\x95\xe0\xb5\x8d\xe0\xb4\x95");
    CHECK(cursor_col(t) == 2, "virama conjunct is two columns");
    feed(t, "\r\n");
    /* Combining accent joins its base: e + U+0301. */
    feed(t, "e\xcc\x81");
    CHECK(cursor_col(t) == 1, "combining mark takes no column");
    CHECK(strcmp(cell_text(t, 3, 0, buf, sizeof buf), "e\xcc\x81") == 0,
          "combining mark stored with its base");
    starling_term_free(t);
}

/* ---- identity queries ---------------------------------------------------- */

static void test_identity(void) {
    printf("identity queries:\n");
    StarlingTerm *t = fresh(80, 24);
    feed(t, "\033[c");
    CHECK(strcmp(resp(), "\033[?6c") == 0, "DA1 answers VT102");
    resp_clear();
    feed(t, "\033[>c");
    CHECK(strcmp(resp(), "\033[>1;10;0c") == 0, "DA2 answers, '>'-shaped");
    resp_clear();
    feed(t, "\033[>q");
    CHECK(strcmp(resp(), "\033P>|Starling Terminal\033\\") == 0,
          "XTVERSION names the terminal");
    resp_clear();
    /* DECRQCRA on *y, xterm's negated checksum: lone 'A' reads 0xFFBF. */
    feed(t, "\033[2J\033[H" "A");
    feed(t, "\033[1;1;1;1;1;1*y");
    CHECK(strcmp(resp(), "\033P1!~FFBF\033\\") == 0,
          "DECRQCRA checksums like xterm (lone 'A' = FFBF)");
    starling_term_free(t);
}

int main(void) {
    test_widths();
    test_wide_wrap_and_pairs();
    test_vs_and_flags();
    test_clusters();
    test_identity();
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("all passed\n");
    return 0;
}
