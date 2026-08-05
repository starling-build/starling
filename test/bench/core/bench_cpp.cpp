// A C++ terminal core implementing the same hot path as TerminalEmulator.swift:
// UTF-8 decode, ground-state printing into the grid, the ESC/CSI state machine,
// SGR (including 256-colour), cursor addressing, erase, and scroll with
// scrollback. Written the natural C++ way — flat array, per-character writes,
// switch-based state machine — with NO run fast path, because the point is to
// find out what the per-cell write costs without Swift's exclusivity/ARC/COW
// bookkeeping.
//
// SUBSET, deliberately: it covers what the benchmark streams exercise. It is an
// upper bound on what porting would buy, not a drop-in replacement.
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cstdlib>
#include <vector>
#include <deque>
#include <chrono>

struct Cell {
    uint32_t scalar = 32;
    uint32_t fg = 0;
    uint32_t bg = 0;
    uint32_t attrs = 0;
};
static_assert(sizeof(Cell) == 16, "match Swift TermCell layout");

class Emu {
public:
    Emu(int cols, int rows) : cols_(cols), rows_(rows), grid_(size_t(cols) * rows) {
        blank_.scalar = 32;
    }

    void feed(const uint8_t* p, size_t n) {
        for (size_t i = 0; i < n; ) {
            uint8_t b = p[i];

            if (state_ == Ground) {
                if (b >= 0x20 && b < 0x7F) { putScalar(b); ++i; continue; }
                if (b >= 0x80) {                       // UTF-8 lead
                    int len = b >= 0xF0 ? 4 : b >= 0xE0 ? 3 : b >= 0xC0 ? 2 : 1;
                    if (i + len > n) { break; }        // partial: benchmark feeds whole chunks
                    uint32_t v = 0;
                    switch (len) {
                        case 2: v = ((b & 0x1F) << 6) | (p[i+1] & 0x3F); break;
                        case 3: v = ((b & 0x0F) << 12) | ((p[i+1] & 0x3F) << 6) | (p[i+2] & 0x3F); break;
                        case 4: v = ((b & 0x07) << 18) | ((p[i+1] & 0x3F) << 12) |
                                    ((p[i+2] & 0x3F) << 6) | (p[i+3] & 0x3F); break;
                        default: v = b; break;
                    }
                    putScalar(v); i += len; continue;
                }
            }
            processByte(b); ++i;
        }
    }

    uint64_t writes = 0;

    size_t checksum() const {            // keeps the optimiser honest
        size_t s = 0;
        for (const Cell& c : grid_) s += c.scalar + c.fg + c.bg;
        return s + scrollback_.size();
    }

private:
    enum State { Ground, Escape, Csi };

    void processByte(uint8_t b) {
        switch (state_) {
        case Ground:
            switch (b) {
            case 0x1B: state_ = Escape; break;
            case '\n': lineFeed(); break;
            case '\r': cursorCol_ = 0; wrapPending_ = false; break;
            case '\b': if (cursorCol_ > 0) --cursorCol_; wrapPending_ = false; break;
            case '\t': cursorCol_ = (cursorCol_ / 8 + 1) * 8;
                       if (cursorCol_ >= cols_) cursorCol_ = cols_ - 1; break;
            default: break;
            }
            break;
        case Escape:
            if (b == '[') { state_ = Csi; nparam_ = 0; param_[0] = -1; priv_ = false; }
            else state_ = Ground;
            break;
        case Csi:
            if (b >= '0' && b <= '9') {
                if (param_[nparam_] < 0) param_[nparam_] = 0;
                param_[nparam_] = param_[nparam_] * 10 + (b - '0');
            } else if (b == ';') {
                if (nparam_ + 1 < kMaxParams) { ++nparam_; param_[nparam_] = -1; }
            } else if (b == '?') {
                priv_ = true;
            } else if (b >= 0x40 && b <= 0x7E) {
                dispatchCsi(b); state_ = Ground;
            }
            break;
        }
    }

    int param(int i, int dflt) const {
        if (i > nparam_) return dflt;
        return param_[i] < 0 ? dflt : param_[i];
    }

    void dispatchCsi(uint8_t f) {
        if (priv_) return;                       // ?1049h / ?25l — no-ops here
        switch (f) {
        case 'H': case 'f': {
            int r = param(0, 1) - 1, c = param(1, 1) - 1;
            cursorRow_ = r < 0 ? 0 : (r >= rows_ ? rows_ - 1 : r);
            cursorCol_ = c < 0 ? 0 : (c >= cols_ ? cols_ - 1 : c);
            wrapPending_ = false;
            break;
        }
        case 'J': {
            int m = param(0, 0);
            size_t from = 0, to = grid_.size();
            if (m == 0) from = size_t(cursorRow_) * cols_ + cursorCol_;
            else if (m == 1) to = size_t(cursorRow_) * cols_ + cursorCol_ + 1;
            Cell b = blank_; b.bg = curBg_;
            for (size_t i = from; i < to; ++i) grid_[i] = b;
            break;
        }
        case 'K': {
            int m = param(0, 0);
            size_t rowStart = size_t(cursorRow_) * cols_;
            size_t from = rowStart + cursorCol_, to = rowStart + cols_;
            if (m == 1) { from = rowStart; to = rowStart + cursorCol_ + 1; }
            else if (m == 2) { from = rowStart; }
            Cell b = blank_; b.bg = curBg_;
            for (size_t i = from; i < to; ++i) grid_[i] = b;
            break;
        }
        case 'm': applySgr(); break;
        default: break;
        }
    }

    void applySgr() {
        if (nparam_ == 0 && param_[0] < 0) { curFg_ = curBg_ = curAttrs_ = 0; return; }
        for (int i = 0; i <= nparam_; ++i) {
            int v = param(i, 0);
            if (v == 0) { curFg_ = curBg_ = curAttrs_ = 0; }
            else if (v == 1) curAttrs_ |= 1;
            else if (v == 4) curAttrs_ |= 2;
            else if (v == 7) curAttrs_ |= 4;
            else if (v >= 30 && v <= 37) curFg_ = palette(v - 30);
            else if (v >= 40 && v <= 47) curBg_ = palette(v - 40);
            else if (v >= 90 && v <= 97) curFg_ = palette(v - 90 + 8);
            else if (v >= 100 && v <= 107) curBg_ = palette(v - 100 + 8);
            else if (v == 39) curFg_ = 0;
            else if (v == 49) curBg_ = 0;
            else if ((v == 38 || v == 48) && i + 1 <= nparam_) {
                int mode = param(i + 1, 0);
                if (mode == 5 && i + 2 <= nparam_) {
                    uint32_t c = palette(param(i + 2, 0)); i += 2;
                    if (v == 38) curFg_ = c; else curBg_ = c;
                } else if (mode == 2 && i + 4 <= nparam_) {
                    uint32_t c = 0xFF000000u | (uint32_t(param(i+2,0)) << 16)
                               | (uint32_t(param(i+3,0)) << 8) | uint32_t(param(i+4,0));
                    i += 4;
                    if (v == 38) curFg_ = c; else curBg_ = c;
                }
            }
        }
    }

    static uint32_t palette(int idx) { return 0xFF000000u | uint32_t(idx * 2654435761u); }

    void putScalar(uint32_t v) {
        if (wrapPending_) { cursorCol_ = 0; lineFeed(); wrapPending_ = false; }
        if (cursorCol_ >= cols_) { cursorCol_ = 0; lineFeed(); }
        ++writes;
        Cell& c = grid_[size_t(cursorRow_) * cols_ + cursorCol_];
        c.scalar = v; c.fg = curFg_; c.bg = curBg_; c.attrs = curAttrs_;
        if (cursorCol_ + 1 >= cols_) { cursorCol_ = cols_ - 1; wrapPending_ = true; }
        else ++cursorCol_;
    }

    void lineFeed() {
        if (cursorRow_ + 1 >= rows_) scrollUp();
        else ++cursorRow_;
        wrapPending_ = false;
    }

    void scrollUp() {
        // Same shape as the Swift side: push the top row to scrollback, shift
        // up, blank the last row, and trim scrollback with slack.
        scrollback_.emplace_back(grid_.begin(), grid_.begin() + cols_);
        std::memmove(grid_.data(), grid_.data() + cols_,
                     (grid_.size() - cols_) * sizeof(Cell));
        Cell b = blank_; b.bg = curBg_;
        for (int i = 0; i < cols_; ++i) grid_[grid_.size() - cols_ + i] = b;
        if (scrollback_.size() > 2000 + 512) {
            while (scrollback_.size() > 2000) scrollback_.pop_front();
        }
    }

    int cols_, rows_;
    std::vector<Cell> grid_;
    std::deque<std::vector<Cell>> scrollback_;
    Cell blank_;
    int cursorRow_ = 0, cursorCol_ = 0;
    bool wrapPending_ = false;
    State state_ = Ground;
    static constexpr int kMaxParams = 32;
    int param_[kMaxParams] = {-1};
    int nparam_ = 0;
    bool priv_ = false;
    uint32_t curFg_ = 0, curBg_ = 0, curAttrs_ = 0;
};

int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "/var/tmp/bench/doomstream.bin";
    int reps = argc > 2 ? atoi(argv[2]) : 3;
    FILE* f = fopen(path, "rb");
    if (!f) { fprintf(stderr, "cannot read %s\n", path); return 1; }
    fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
    const size_t nbytes = static_cast<size_t>(sz);
    std::vector<uint8_t> buf(nbytes);
    if (fread(buf.data(), 1, nbytes, f) != nbytes) { fprintf(stderr, "short read\n"); return 1; }
    fclose(f);
    printf("stream %ld MB, chunk 65536, grid 47x201\n", sz / 1000000);

    const size_t chunk = 65536;
    for (int r = 1; r <= reps; ++r) {
        Emu em(201, 47);
        auto t0 = std::chrono::steady_clock::now();
        for (size_t i = 0; i < buf.size(); i += chunk)
            em.feed(buf.data() + i, std::min(chunk, buf.size() - i));
        auto t1 = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(t1 - t0).count();
        printf("run %d  %.3f s  %.1f MB/s  cellwrites %llu  [checksum %zu]\n",
               r, secs, double(sz) / 1e6 / secs,
               (unsigned long long)em.writes, em.checksum());
    }
    return 0;
}
