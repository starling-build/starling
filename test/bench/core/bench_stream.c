/* Our core, consuming a file exactly the way ghostty-bench does — so the two
 * can be compared.
 *
 * `bench_st.c` slurps the whole corpus into memory and then times the feed,
 * which is the right shape for measuring OUR core against ITSELF. It is the
 * wrong shape for measuring it against `ghostty-bench +terminal-stream`, which
 * reads the data file in 64 KB chunks inside the timed region (their
 * TerminalStream.zig picks 64 KB deliberately: it is the buffer_capacity of
 * their real IO thread). Comparing the two directly would charge us nothing
 * for file I/O and them the full amount.
 *
 * So this harness mirrors theirs: open, read 64 KB at a time, feed, exit —
 * one pass, no repetitions, print nothing. Their runner discards its own
 * timing result (`b.run(.once)` in benchmark/cli.zig) and their docs say to
 * time the process with hyperfine, so the comparison is process wall against
 * process wall, and both sides must therefore do the same amount of work
 * outside the parser too.
 *
 *   bench_stream <file> [cols rows]
 *   STREAM_NOOP=1   read and discard — the I/O floor to subtract from both
 *                   sides, the same trick their codepoint-width `noop` mode
 *                   exists for.
 *
 * Note there is no ONLCR expansion here, unlike bench_st: ghostty-gen emits
 * CRLF itself, so a generated corpus already carries its CRs and both sides
 * see identical bytes. Feeding it through bench_st's expansion would not
 * change it (that only fires when a stream has LFs and no CRs), but reading
 * the file straight through keeps this harness honest about what it measured.
 */
#include "starling_term.h"
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: bench_stream <file> [cols rows]\n"); return 2; }
    const char *path = argv[1];
    int cols = argc > 2 ? atoi(argv[2]) : 201;
    int rows = argc > 3 ? atoi(argv[3]) : 47;
    int noop = getenv("STREAM_NOOP") != NULL;

    int fd = open(path, O_RDONLY);
    if (fd < 0) { perror("open"); return 1; }

    StarlingTerm *t = noop ? NULL : starling_term_new(cols, rows);
    static unsigned char buf[64 * 1024];
    unsigned long long total = 0;
    for (;;) {
        ssize_t n = read(fd, buf, sizeof buf);
        if (n < 0) { if (errno == EINTR) continue; perror("read"); return 1; }
        if (n == 0) break;
        total += (unsigned long long)n;
        if (!noop) starling_term_feed(t, buf, (size_t)n);
    }
    close(fd);
    if (t) starling_term_free(t);
    /* stderr so stdout stays empty, like theirs */
    fprintf(stderr, "%llu\n", total);
    return 0;
}
