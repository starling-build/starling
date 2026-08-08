// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

#ifndef STARLING_NVENC_ENCODER_H
#define STARLING_NVENC_ENCODER_H

#include <stdint.h>

// In-process H.264 encoding on an NVIDIA GPU through NVENC — the NVIDIA
// sibling of vaapi_encoder.h, same session shape, same MP4 muxer, no
// ffmpeg child. libcuda and libnvidia-encode are dlopen'd: they exist only
// on machines running the NVIDIA driver, and a hard -l link would make the
// shell unloadable everywhere else (the same reason the old libav path was
// dlopen'd — see record/Package.swift).
//
// Input frames must be NVIDIA-RESIDENT linear DRM_FORMAT_ABGR8888
// dma-bufs: recording is per-screen and each screen's shell is encoded by
// the GPU that renders it, so frames never cross GPUs. The dma-buf imports
// into CUDA (cuImportExternalMemory — the driver accepts its own buffers
// through OPAQUE_FD) and registers with NVENC as a device pointer: true
// zero-copy, the NVIDIA mirror of VAAPI's DRM_PRIME_2 import. A foreign
// (AMD-allocated) fd fails the import, by design.

#ifdef __cplusplus
extern "C" {
#endif

typedef struct NvencEncoder NvencEncoder;

/// 1 when an NVENC session can actually open (libraries load, a CUDA
/// device exists, a throwaway 256x256 session initializes), else 0.
int nvenc_encoder_probe(void);

/// Open a session: CUDA context, NVENC session, input/bitstream buffers,
/// MP4 muxer on out_path. Input dims are the engine ring's (may be odd);
/// output dims must be even (the odd row/column is cropped in the copy).
/// qp keeps the pipe path's meaning as a quality knob: it selects the VBR
/// bits-per-pixel budget exactly like the VAAPI encoder does.
/// NULL on failure, and no file is left behind.
NvencEncoder* nvenc_encoder_open(int in_w, int in_h,
                                 int out_w, int out_h,
                                 int fps, int qp, const char* out_path);

/// Encode one dma-buf frame (borrowed fd, engine-owned — never closed
/// here). fourcc must be DRM_FORMAT_ABGR8888/XBGR8888 and the layout
/// linear. 0 on success; nonzero means the session is dead — read
/// nvenc_encoder_error, then finish or abort.
int nvenc_encoder_encode(NvencEncoder* e, int fd,
                         uint32_t stride, uint32_t offset,
                         uint32_t fourcc, uint64_t modifier,
                         uint64_t pts_us);

/// Frames encoded so far.
int nvenc_encoder_frame_count(NvencEncoder* e);

/// Finalize the MP4. 0 on success (handle freed); nonzero leaves the
/// handle alive so the error is readable — follow with abort.
int nvenc_encoder_finish(NvencEncoder* e);

/// Tear down and unlink the partial file.
void nvenc_encoder_abort(NvencEncoder* e);

/// Last error, valid until the next call on the handle.
const char* nvenc_encoder_error(NvencEncoder* e);

#ifdef __cplusplus
}
#endif

#endif  // STARLING_NVENC_ENCODER_H
