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

/* ---- resize ------------------------------------------------------------- */

/* First row of the live grid, as text, so a test can say which line is on top. */
static const char *top_line(StarlingTerm *t, char *buf, int cap) {
    StarlingTermCell line[512];
    starling_term_copy_line(t, starling_term_scrollback_count(t), line);
    int n = 0;
    for (int c = 0; c < starling_term_cols(t) && n < cap - 1; c++) {
        if (line[c].scalar == 32 || line[c].scalar == 0) break;
        n += starling_term_cell_text(t, line[c].scalar, buf + n, cap - 1 - n);
    }
    buf[n] = 0;
    return buf;
}

static void test_resize(void) {
    printf("resize:\n");
    char buf[64];

    /* Grow appends blank rows at the bottom; shrink used to take rows off the
     * top unconditionally, so the two were not inverses. Found on Windows in
     * TerminalTiling: a 31-row floating pane switched to a 36-row tiled one
     * and back showed "17" on top instead of "11" — six lines scrolled away
     * with five blank rows still sitting under the cursor. A pane whose output
     * sits near the top loses all of it in one switch and reads as a repaint
     * bug, which is how this was first reported. */
    StarlingTerm *t = fresh(80, 31);
    for (int i = 1; i <= 40; i++) { char s[16]; sprintf(s, "%d\r\n", i); feed(t, s); }
    CHECK(strcmp(top_line(t, buf, sizeof buf), "11") == 0,
          "40 lines into 31 rows leaves 11 on top");

    int sb_before = starling_term_scrollback_count(t);
    starling_term_resize(t, 80, 36);
    CHECK(strcmp(top_line(t, buf, sizeof buf), "11") == 0,
          "growing keeps the top line");
    starling_term_resize(t, 80, 31);
    CHECK(strcmp(top_line(t, buf, sizeof buf), "11") == 0,
          "shrinking back is a no-op, not six lines of loss");
    CHECK(starling_term_scrollback_count(t) == sb_before,
          "a grow/shrink round trip pushes nothing to scrollback");

    /* The other half of the contract: with no blank rows to reclaim, a shrink
     * must still evict from the top, and into scrollback. */
    starling_term_resize(t, 80, 28);
    CHECK(strcmp(top_line(t, buf, sizeof buf), "14") == 0,
          "a real shrink still scrolls the top away");
    CHECK(starling_term_scrollback_count(t) == sb_before + 3,
          "and the evicted rows land in scrollback");
    starling_term_free(t);

    /* The reported symptom in its original shape: a nearly empty pane, content
     * at the very top, shrunk by a mode switch. Every line survived nothing
     * before this. */
    t = fresh(80, 30);
    feed(t, "hello\r\nworld\r\n");
    starling_term_resize(t, 80, 8);
    CHECK(strcmp(top_line(t, buf, sizeof buf), "hello") == 0,
          "shrinking a mostly blank pane keeps its content");
    starling_term_free(t);
}

/* ---- OSC 7: where the shell says it is ----------------------------------- */

/* The first OSC payload the parser keeps rather than discards, and the thing
 * that lets a restored pane come back in its own directory instead of $HOME.
 * Every case below is one a shell actually emits — including the ones that
 * must be REFUSED, because a bad answer here reopens a pane somewhere the
 * person never was. */
static void test_osc_cwd(void) {
    StarlingTerm *t = fresh(20, 4);
    CHECK(starling_term_cwd(t)[0] == 0, "cwd starts empty, not \"/\"");

    feed(t, "\x1b]7;file://host/home/dev/starling\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/home/dev/starling"),
          "OSC 7 with BEL sets the directory");

    /* ST-terminated is the other spelling, and the one zsh sends. */
    feed(t, "\x1b]7;file://host/tmp\x1b\\");
    CHECK(!strcmp(starling_term_cwd(t), "/tmp"), "OSC 7 with ST sets it too");

    /* Percent escapes: a space in a path is the common one. */
    feed(t, "\x1b]7;file://host/home/dev/my%20work\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/home/dev/my work"),
          "percent escapes are decoded");

    /* An empty host is legal and common (file:///path). */
    feed(t, "\x1b]7;file:///srv\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "an empty host still yields a path");

    /* Anything that is not a path leaves the last good answer alone: a pane
     * reopened in the wrong directory is worse than one reopened in $HOME. */
    feed(t, "\x1b]7;file://host\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "a URL with no path is ignored");
    feed(t, "\x1b]7;relative/path\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "a relative path is ignored");
    feed(t, "\x1b]7;file://host/bad%00path\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "an escaped control byte is refused");

    /* Other OSC numbers are not OSC 7 — including the ones that start with a
     * 7, which is what a sloppy prefix test would fall for. */
    feed(t, "\x1b]70;file://host/wrong\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "OSC 70 is not OSC 7");
    feed(t, "\x1b]0;a title\x07");
    CHECK(!strcmp(starling_term_cwd(t), "/srv"), "a title does not move the directory");

    /* And the sequence still consumes itself: none of it may reach the grid. */
    /* The BEL is split off its own string literal: "\x07A" is one hex escape
       for 0x7A, which is the letter z. */
    feed(t, "\x1b]7;file://host/x\x07" "AB");
    CHECK(cell_at(t, 0, 0).scalar == 'A' && cell_at(t, 0, 1).scalar == 'B',
          "the sequence is consumed, not printed");

    starling_term_free(t);
}

/* OSC 133 — the shell integration marks that say whether a pane is waiting
 * for you or working. What matters here is not that A/B/C/D set a state (they
 * obviously do) but the three ways a naive reading badges a pane wrongly: an
 * exit code of 0 confused with "no exit code", a D that no C preceded, and a
 * shell that says nothing at all being reported as idle. */
static void test_osc_command(void) {
    StarlingTerm *t = fresh(20, 4);
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_UNKNOWN,
          "a shell that has said nothing is UNKNOWN, not idle");
    CHECK(starling_term_command_exit(t) == -1, "and has no exit code");
    CHECK(starling_term_command_done_count(t) == 0, "and has finished nothing");

    feed(t, "\x1b]133;A\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_PROMPT,
          "OSC 133;A is a prompt");
    feed(t, "\x1b]133;B\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_PROMPT,
          "OSC 133;B is also a prompt");

    feed(t, "\x1b]133;C\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_RUNNING,
          "OSC 133;C is a command running");
    CHECK(starling_term_command_done_count(t) == 0, "which has not finished yet");

    feed(t, "\x1b]133;D;0\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_DONE,
          "OSC 133;D finishes it");
    CHECK(starling_term_command_exit(t) == 0, "exit 0 is success, not \"no code\"");
    CHECK(starling_term_command_done_count(t) == 1, "and it counts as one command");

    /* A failure, and the ST spelling. */
    feed(t, "\x1b]133;C\x1b\\");
    feed(t, "\x1b]133;D;127\x1b\\");
    CHECK(starling_term_command_exit(t) == 127, "a real exit code is kept");
    CHECK(starling_term_command_done_count(t) == 2, "and counted");

    /* D with no code at all: finished, but nothing to say about how. */
    feed(t, "\x1b]133;C\x07");
    feed(t, "\x1b]133;D\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_DONE, "a bare D finishes");
    CHECK(starling_term_command_exit(t) == -1, "with no exit code");
    CHECK(starling_term_command_done_count(t) == 3, "still a command that ran");

    /* Shells emit D at startup and after a bare Enter. Counting those badges
     * a pane in which nobody has run anything. */
    uint64_t before = starling_term_command_done_count(t);
    feed(t, "\x1b]133;D;0\x07");
    CHECK(starling_term_command_done_count(t) == before,
          "a D with no C before it is not a command");

    /* Parameters after the letter are other people's business, not ours. */
    feed(t, "\x1b]133;A;aid=7;cl=m\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_PROMPT,
          "trailing parameters do not confuse A");

    /* Prefix traps, the same shape as OSC 70 vs OSC 7. */
    feed(t, "\x1b]133;C\x07");
    feed(t, "\x1b]1337;File=name\x07");
    CHECK(starling_term_command_state(t) == STARLING_TERM_CMD_RUNNING,
          "OSC 1337 is not OSC 133");

    /* And it consumes itself. */
    feed(t, "\x1b]133;D;0\x07" "AB");
    CHECK(cell_at(t, 0, 0).scalar == 'A' && cell_at(t, 0, 1).scalar == 'B',
          "the sequence is consumed, not printed");

    starling_term_free(t);
}

/* ---- keyboard-protocol controls that end in 'm' ---------------------------- */

static void test_modkeys_are_not_sgr(void) {
    printf("modifyOtherKeys controls are not SGR:\n");
    StarlingTerm *t = fresh(80, 24);
    /* vim's t_TI: set modifyOtherKeys. Read as SGR 4;2 it underlined and
       dimmed everything after it. */
    feed(t, "\033[>4;2m" "a");
    CHECK(cell_at(t, 0, 0).attrs == 0, "ESC[>4;2m (XTMODKEYS set) sets no attribute");
    /* vim's t_RK: query modifyOtherKeys -- sent right before the search
       prompt is drawn, which is how a search came out underlined. */
    resp_clear();
    feed(t, "\033[?4m" "b");
    CHECK(cell_at(t, 0, 1).attrs == 0, "ESC[?4m (XTQMODKEYS) sets no attribute");
    CHECK(strcmp(resp(), "\033[>4;0m") == 0, "XTQMODKEYS is answered: modifyOtherKeys is 0 here");
    /* vim's t_TE: clear modifyOtherKeys, sent at :q -- read as SGR 4 it
       underlined the shell prompt that followed. */
    feed(t, "\033[>4;m" "c");
    CHECK(cell_at(t, 0, 2).attrs == 0, "ESC[>4;m (XTMODKEYS clear) sets no attribute");
    feed(t, "\033[4m" "d" "\033[24m" "e");
    CHECK((cell_at(t, 0, 3).attrs & STARLING_ATTR_UNDERLINE) != 0, "plain SGR 4 still underlines");
    CHECK(cell_at(t, 0, 4).attrs == 0, "and SGR 24 still clears it");
    starling_term_free(t);
}

int main(void) {
    test_widths();
    test_wide_wrap_and_pairs();
    test_vs_and_flags();
    test_clusters();
    test_identity();
    test_resize();
    test_osc_cwd();
    test_osc_command();
    test_modkeys_are_not_sgr();
    if (fails) { printf("%d FAILED\n", fails); return 1; }
    printf("all passed\n");
    return 0;
}
