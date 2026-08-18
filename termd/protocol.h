// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// The remote-terminal wire format (docs/plans/remote-terminal.md).
//
// Frames are length-prefixed and little-endian. The payload of a DATA frame
// is the pty byte stream verbatim — the server never re-encodes a screen,
// which is the whole point of the design, so this file describes framing
// and almost nothing else.

#ifndef STARLING_TERMD_PROTOCOL_H
#define STARLING_TERMD_PROTOCOL_H

#include <stdint.h>

// 2 added session names: LIST_REPLY entries are variable-length now, and
// OPEN carries a name before its command, so a v1 client cannot read a v2
// reply. Both ends ship together; the version is here to make a mismatch a
// clean refusal rather than a misparse.
#define TERMD_PROTOCOL_VERSION 2

// struct frame { u8 type; u8 flags; u16 pad; u32 len; u8 payload[len]; }
#define TERMD_HEADER_LEN 8
// A DATA payload never exceeds this, so a client can size one buffer.
#define TERMD_MAX_PAYLOAD (1u << 20)

// A session name, NUL excluded. Names are how humans address a session —
// "iOS dev" rather than 12 — and the daemon treats them as opaque bytes
// apart from dropping control characters and trimming edge whitespace.
#define TERMD_MAX_NAME 64

// A layout blob is a client's private format and the daemon only stores it.
// The cap is generous for a tree of pane ratios and mean about anything else,
// which is the point: it is a layout, not a place to keep state.
#define TERMD_MAX_BLOB (16u * 1024u)
#define TERMD_MAX_WORKSPACES 32

// What a daemon can be asked for, reported as a trailing byte on HELLO_OK. A
// client that sees a SHORT hello reply is talking to a daemon that predates
// the byte and must assume nothing.
//
// Bit 0: a session's `command` is run by a POSIX shell. It is the client that
// composes those commands — reopening a pane in its old directory is
// `cd '<dir>' && exec "$STARLING_SHELL"` — and on a daemon whose shell is
// cmd.exe that string is not a command, it is a pane that exits before it
// draws. The daemon knows which it is; the client cannot guess.
#define TERMD_CAP_POSIX_SHELL 0x01u

// Bit 1: the daemon can report a session's working directory
// (TERMD_SESSION_CWD). It cannot on Windows, where reading another process's
// current directory means injecting into it, so a client asks only when this
// is set — an unknown frame is answered with an ERROR, not silence.
#define TERMD_CAP_SESSION_CWD 0x02u

enum termd_type {
    TERMD_HELLO = 1,       // → version u16, name
    TERMD_HELLO_OK = 2,    // ← version u16, session count u16,
                           //   caps u8 (OPTIONAL, trailing — see TERMD_CAP_*)
    TERMD_LIST = 3,        // →
    TERMD_LIST_REPLY = 4,  // ← count u16, then count × { id u32, cols u16,
                           //   rows u16, alive u8, seq u64, name_len u16,
                           //   name[name_len] } — entries are variable-length
    TERMD_OPEN = 5,        // → cols u16, rows u16, name_len u16, name[name_len],
                           //   command (rest, may be empty). A named OPEN is
                           //   idempotent: if a session already has that name
                           //   the daemon attaches to it — from the oldest byte
                           //   it still holds — instead of forking a second
                           //   shell, and answers ATTACHED either way. That is
                           //   what makes a name a durable handle: a client
                           //   that lost its id reconnects with the name alone.
    TERMD_ATTACH = 6,      // → id u32, from_seq u64, cols u16, rows u16,
                           //   max_replay u32 (OPTIONAL, trailing): send at
                           //   most this many bytes of backlog — the tail, not
                           //   the whole ring. 0 or absent means everything
                           //   still held. Trailing so a client that predates
                           //   it is unchanged, and no version bump: a shorter
                           //   payload is the old meaning exactly.
    TERMD_ATTACHED = 7,    // ← id u32, from_seq u64 (what will actually be sent)
    TERMD_DATA = 8,        // ← seq u64, bytes
    TERMD_INPUT = 9,       // → bytes
    TERMD_RESIZE = 10,     // → cols u16, rows u16
    TERMD_ACK = 11,        // → seq u64 consumed through
    TERMD_EXIT = 12,       // ← id u32, status i32
    TERMD_DETACH = 13,     // →
    TERMD_ERROR = 14,      // ← code u16, message
    TERMD_PING = 15,       // ↔ (either side; the other answers PONG)
    TERMD_PONG = 16,       // ↔

    // Workspaces (v1 of docs/plans/remote-workspace.md). A workspace is a
    // NAME, a set of sessions, and an opaque blob. The daemon stores the blob
    // and hands it back; it never parses it. Split ratios, focus and pane
    // titles live inside it, so a new layout feature is a client change rather
    // than a protocol one — and the daemon needs no idea what a pane is.
    //
    // Sessions are joined to a workspace by a separate frame rather than a
    // field on OPEN: OPEN's payload ends with "command (rest)", so it has no
    // room to grow at the end, and putting the id in the middle would break
    // every client that predates it. WS_ADD is additive and needs no version
    // bump. Session ids are never reused (g_next_id only increments), so a
    // membership list cannot come to mean a different session later.
    TERMD_WS_CREATE = 17,  // → name_len u16, name  — idempotent by name, like
                           //   a named OPEN: asking twice returns the same id
    TERMD_WS_INFO = 18,    // ← ws_id u32, name_len u16, name  (also the reply
                           //   to WS_ADD and WS_SET_META, so a client knows
                           //   the write landed)
    TERMD_WS_LIST = 19,    // →
    TERMD_WS_LIST_REPLY = 20,
                           // ← count u16, then count × { ws_id u32,
                           //   blob_len u32, nsessions u16,
                           //   sessions[nsessions] u32, name_len u16, name }
    TERMD_WS_ADD = 21,     // → ws_id u32, session u32
    TERMD_WS_SET_META = 22,// → ws_id u32, blob (rest)
    TERMD_WS_GET_META = 23,// → ws_id u32
    TERMD_WS_META = 24,    // ← ws_id u32, blob (rest). Answers WS_GET_META,
                           //   and is also sent UNASKED to every other
                           //   connection watching that workspace whenever
                           //   one of them stores a new arrangement. Without
                           //   it, two clients on one workspace each keep
                           //   drawing their own tree and writing it over the
                           //   other's. A connection starts watching by
                           //   naming a workspace in any WS_ frame.

    TERMD_SESSION_CWD = 25,// → id u32 — where is this session's shell?
    TERMD_SESSION_CWD_REPLY = 26,
                           // ← id u32, path (rest, may be empty when the
                           //   daemon could not read it). Only ask when
                           //   HELLO_OK advertised TERMD_CAP_SESSION_CWD:
                           //   an unknown frame is an ERROR, not silence.
                           //
                           //   The client stores this in its layout blob so a
                           //   pane can be reopened where it was. It could
                           //   read OSC 7 from the byte stream instead — and
                           //   does, preferring it, since it needs no round
                           //   trip — but a great many shells never emit one:
                           //   macOS ships zsh sending it to Apple Terminal
                           //   alone. The daemon owns the pty, so it can just
                           //   ask the kernel, and that works for every shell.
};

enum termd_error {
    TERMD_ERR_NO_SESSION = 1,
    TERMD_ERR_BAD_FRAME = 2,
    TERMD_ERR_VERSION = 3,
    TERMD_ERR_OPEN_FAILED = 4,
    TERMD_ERR_NO_WORKSPACE = 5,
    TERMD_ERR_TOO_MANY = 6,
};

#endif  // STARLING_TERMD_PROTOCOL_H
