// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#ifndef STARLING_MP4_MUX_H
#define STARLING_MP4_MUX_H

#include <stddef.h>
#include <stdint.h>

// A single-track H.264 MP4 writer — the counterpart to VideoPlayerApp's
// mp4_demux.c, and the reason this encoder needs no libavformat.
//
// Deliberately narrow, in the same spirit as the decoder: one video track, no
// audio, no edit lists, no fragments, progressive frames in decode order
// (which is also presentation order, because nothing here emits B-frames).
//
// Samples stream to disk as they arrive and the index is held in memory until
// `finish`, which appends `moov` and patches the `mdat` size. That ordering
// means the file is NOT faststart — the index is at the end. For recordings
// opened from local disk that costs nothing, and writing moov first would
// mean either buffering the whole recording in RAM or a rewrite pass over a
// file that can be gigabytes.

typedef struct Mp4Mux Mp4Mux;

/// Open `path` and write the file header. `timescale` is in ticks per second
/// for the media timeline; sample times are given in those ticks.
/// `sps`/`pps` are bare NALs, escaped, with no start code — as avcC stores
/// them. NULL on failure.
Mp4Mux* mp4_mux_open(const char* path, int width, int height,
                     uint32_t timescale,
                     const uint8_t* sps, size_t sps_len,
                     const uint8_t* pps, size_t pps_len);

/// Append one access unit. `data` is Annex-B (start codes); the muxer
/// rewrites it to the 4-byte length prefixes MP4 requires, dropping any
/// SPS/PPS NALs since those live in avcC. `dts` is in timescale ticks.
/// Returns 0 on success.
int mp4_mux_write_sample(Mp4Mux* m, const uint8_t* data, size_t size,
                         uint64_t dts, int is_keyframe);

/// Number of samples written so far.
int64_t mp4_mux_sample_count(const Mp4Mux* m);

/// Write the index and close. 0 on success, and the handle is then freed.
/// On failure the handle stays live so `mp4_mux_error` can be read — follow
/// with `mp4_mux_abort`. Same contract as vaapi_encoder_finish, which is its
/// only caller.
int mp4_mux_finish(Mp4Mux* m);

/// Close and free without writing an index. The file is left partial — the
/// caller unlinks it.
void mp4_mux_abort(Mp4Mux* m);

/// Last error, or "".
const char* mp4_mux_error(const Mp4Mux* m);

#endif  // STARLING_MP4_MUX_H
