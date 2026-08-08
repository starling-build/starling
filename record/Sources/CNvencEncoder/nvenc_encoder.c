// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// H.264 encoding through NVENC — NVIDIA's encoder API, driven directly.
//
// Shape mirrors vaapi_encoder.c: open a session, feed the engine ring's
// linear ABGR8888 dma-bufs, hand access units to mp4_mux, finish or abort.
// Differences that matter:
//
//  - libcuda.so.1 and libnvidia-encode.so.1 are dlopen'd, never linked:
//    they only exist under the NVIDIA driver, and this code must sit
//    harmlessly inside the shell on AMD-only machines (probe returns 0).
//  - NVENC writes its own SPS/PPS (nvEncGetSequenceParams), so none of
//    h264_headers.c's hand-written parameter sets — and none of the
//    pic_init_qp=26 driver archaeology — applies here.
//  - Input frames must be NVIDIA-resident: this encoder records what its
//    own GPU rendered, never a cross-GPU copy (each screen's shell is
//    encoded by the GPU that renders it). The dma-buf reaches CUDA
//    through EGL interop — eglCreateImageKHR, then
//    cuGraphicsEGLRegisterImage to a pitch-linear device pointer that
//    registers with NVENC — true zero-copy, the NVIDIA mirror of VAAPI's
//    DRM_PRIME_2 import. (cuImportExternalMemory cannot do this: its
//    OPAQUE_FD type rejects gbm dma-bufs outright, error 999.)
//  - Rate control copies ve_send_rate_control's budget: qp selects a
//    bits-per-pixel target (0.15 at qp 24), clamped to 4–30 Mbps VBR with
//    peak at 1.5x, GOP = 2s of frames, IPP only.

#include "nvenc_encoder.h"

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <ffnvcodec/dynlink_cuda.h>
#include <ffnvcodec/nvEncodeAPI.h>

#include "mp4_mux.h"

#define NE_TIMESCALE 1000000  // µs, same 1:1 mapping as VE_TIMESCALE

#ifndef DRM_FORMAT_ABGR8888
#define DRM_FORMAT_ABGR8888 0x34324241  // 'AB24' — R at byte 0 in memory
#endif
#ifndef DRM_FORMAT_XBGR8888
#define DRM_FORMAT_XBGR8888 0x34324258  // 'XB24'
#endif
#ifndef DRM_FORMAT_MOD_LINEAR
#define DRM_FORMAT_MOD_LINEAR 0ULL
#endif
#define DRM_FORMAT_MOD_INVALID_ 0x00ffffffffffffffULL

// ─── dlopen'd entry points ───────────────────────────────────────────────────

typedef CUresult (*ne_cuInit)(unsigned int);
typedef CUresult (*ne_cuDeviceGetCount)(int*);
typedef CUresult (*ne_cuDeviceGet)(CUdevice*, int);
typedef CUresult (*ne_cuCtxCreate)(CUcontext*, unsigned int, CUdevice);
typedef CUresult (*ne_cuCtxDestroy)(CUcontext);
typedef CUresult (*ne_cuCtxPushCurrent)(CUcontext);
typedef CUresult (*ne_cuCtxPopCurrent)(CUcontext*);
// CUDA's EGL interop types — absent from ffnvcodec's minimal header, so
// declared here to match cudaEGL.h's stable ABI.
typedef void* ne_CUgraphicsResource;
typedef struct {
    union {
        void* pArray[3];
        void* pPitch[3];
    } frame;
    unsigned int width, height, depth, pitch, planeCount, numChannels;
    int frameType;  // 1 = CU_EGL_FRAME_TYPE_PITCH
    int eglColorFormat;
    int cuFormat;
} ne_CUeglFrame;

typedef CUresult (*ne_cuGraphicsEGLRegisterImage)(ne_CUgraphicsResource*,
                                                  void* /*EGLImageKHR*/,
                                                  unsigned int);
typedef CUresult (*ne_cuGraphicsResourceGetMappedEglFrame)(
    ne_CUeglFrame*, ne_CUgraphicsResource, unsigned int, unsigned int);
typedef CUresult (*ne_cuGraphicsUnregisterResource)(ne_CUgraphicsResource);
typedef NVENCSTATUS(NVENCAPI* ne_createInstance)(NV_ENCODE_API_FUNCTION_LIST*);

static struct {
    void* cuda;
    void* enc;
    ne_cuInit cuInit;
    ne_cuDeviceGetCount cuDeviceGetCount;
    ne_cuDeviceGet cuDeviceGet;
    ne_cuCtxCreate cuCtxCreate;
    ne_cuCtxDestroy cuCtxDestroy;
    ne_cuCtxPushCurrent cuCtxPush;
    ne_cuCtxPopCurrent cuCtxPop;
    ne_cuGraphicsEGLRegisterImage cuGraphicsEGLRegisterImage;
    ne_cuGraphicsResourceGetMappedEglFrame cuGraphicsResourceGetMappedEglFrame;
    ne_cuGraphicsUnregisterResource cuGraphicsUnregisterResource;

    // EGL, dlopen'd like CUDA (the display is the NVIDIA device's — see
    // ne_egl_display). Core entry points via dlsym, extensions via
    // eglGetProcAddress.
    void* libegl;
    EGLBoolean (*eglInitialize)(EGLDisplay, EGLint*, EGLint*);
    void* (*eglGetProcAddress)(const char*);
    PFNEGLQUERYDEVICESEXTPROC eglQueryDevicesEXT;
    PFNEGLQUERYDEVICESTRINGEXTPROC eglQueryDeviceStringEXT;
    PFNEGLGETPLATFORMDISPLAYEXTPROC eglGetPlatformDisplayEXT;
    PFNEGLCREATEIMAGEKHRPROC eglCreateImageKHR;
    PFNEGLDESTROYIMAGEKHRPROC eglDestroyImageKHR;
    EGLDisplay dpy;  // initialized once, NEVER terminated: EGL device
                     // displays are process-global, and a future NVIDIA
                     // engine view in this process shares this handle.
    NV_ENCODE_API_FUNCTION_LIST fl;
    int loaded;  // 0 untried, 1 ok, -1 failed
} g;

static int ne_load(void) {
    if (g.loaded) return g.loaded == 1;
    g.loaded = -1;
    g.cuda = dlopen("libcuda.so.1", RTLD_NOW | RTLD_LOCAL);
    g.enc = dlopen("libnvidia-encode.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!g.cuda || !g.enc) return 0;
    g.cuInit = (ne_cuInit)dlsym(g.cuda, "cuInit");
    g.cuDeviceGetCount = (ne_cuDeviceGetCount)dlsym(g.cuda, "cuDeviceGetCount");
    g.cuDeviceGet = (ne_cuDeviceGet)dlsym(g.cuda, "cuDeviceGet");
    g.cuCtxCreate = (ne_cuCtxCreate)dlsym(g.cuda, "cuCtxCreate_v2");
    g.cuCtxDestroy = (ne_cuCtxDestroy)dlsym(g.cuda, "cuCtxDestroy_v2");
    g.cuCtxPush = (ne_cuCtxPushCurrent)dlsym(g.cuda, "cuCtxPushCurrent_v2");
    g.cuCtxPop = (ne_cuCtxPopCurrent)dlsym(g.cuda, "cuCtxPopCurrent_v2");
    g.cuGraphicsEGLRegisterImage = (ne_cuGraphicsEGLRegisterImage)dlsym(
        g.cuda, "cuGraphicsEGLRegisterImage");
    g.cuGraphicsResourceGetMappedEglFrame =
        (ne_cuGraphicsResourceGetMappedEglFrame)dlsym(
            g.cuda, "cuGraphicsResourceGetMappedEglFrame");
    g.cuGraphicsUnregisterResource = (ne_cuGraphicsUnregisterResource)dlsym(
        g.cuda, "cuGraphicsUnregisterResource");
    g.libegl = dlopen("libEGL.so.1", RTLD_NOW | RTLD_LOCAL);
    if (!g.libegl) return 0;
    g.eglInitialize = dlsym(g.libegl, "eglInitialize");
    g.eglGetProcAddress = dlsym(g.libegl, "eglGetProcAddress");
    ne_createInstance ci =
        (ne_createInstance)dlsym(g.enc, "NvEncodeAPICreateInstance");
    if (!g.cuInit || !g.cuDeviceGetCount || !g.cuDeviceGet ||
        !g.cuCtxCreate || !g.cuCtxDestroy || !g.cuCtxPush || !g.cuCtxPop ||
        !g.cuGraphicsEGLRegisterImage ||
        !g.cuGraphicsResourceGetMappedEglFrame ||
        !g.cuGraphicsUnregisterResource ||
        !g.eglInitialize || !g.eglGetProcAddress || !ci) {
        return 0;
    }
    g.eglQueryDevicesEXT = (PFNEGLQUERYDEVICESEXTPROC)g.eglGetProcAddress(
        "eglQueryDevicesEXT");
    g.eglQueryDeviceStringEXT = (PFNEGLQUERYDEVICESTRINGEXTPROC)
        g.eglGetProcAddress("eglQueryDeviceStringEXT");
    g.eglGetPlatformDisplayEXT = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
        g.eglGetProcAddress("eglGetPlatformDisplayEXT");
    g.eglCreateImageKHR = (PFNEGLCREATEIMAGEKHRPROC)g.eglGetProcAddress(
        "eglCreateImageKHR");
    g.eglDestroyImageKHR = (PFNEGLDESTROYIMAGEKHRPROC)g.eglGetProcAddress(
        "eglDestroyImageKHR");
    if (!g.eglQueryDevicesEXT || !g.eglQueryDeviceStringEXT ||
        !g.eglGetPlatformDisplayEXT || !g.eglCreateImageKHR ||
        !g.eglDestroyImageKHR) {
        return 0;
    }
    memset(&g.fl, 0, sizeof g.fl);
    g.fl.version = NV_ENCODE_API_FUNCTION_LIST_VER;
    if (ci(&g.fl) != NV_ENC_SUCCESS) return 0;
    if (g.cuInit(0) != CUDA_SUCCESS) return 0;
    int n = 0;
    if (g.cuDeviceGetCount(&n) != CUDA_SUCCESS || n <= 0) return 0;
    g.loaded = 1;
    return 1;
}

// ─── the encoder ─────────────────────────────────────────────────────────────

// Import cache for the ring's dma-bufs, keyed on dev+inode like vaapi's
// import cache (fd numbers get recycled; the ring is a handful of buffers,
// imported and NVENC-registered once each).
#define NE_IMPORT_CACHE 8
typedef struct {
    uint64_t dev, ino;
    uint32_t stride, offset;   // registration is layout-specific
    void* img;                 // EGLImageKHR
    ne_CUgraphicsResource res;
    uint32_t pitch;            // CUDA's word on the mapped layout
    void* reg;                 // NV_ENC_REGISTERED_PTR
} NeImport;

struct NvencEncoder {
    CUcontext cu;
    void* session;
    NV_ENC_OUTPUT_PTR bitstream;
    Mp4Mux* mux;
    char path[512];
    char err[256];
    int in_w, in_h, out_w, out_h, fps;
    int frames;
    uint64_t first_pts;
    NeImport imports[NE_IMPORT_CACHE];
    int import_next;
};

static void ne_set_err(NvencEncoder* e, const char* what, int code) {
    snprintf(e->err, sizeof e->err, "%s failed (%d)", what, code);
}

// Session and context must still be alive: unregister goes through NVENC,
// destroy through CUDA.
static void ne_release_import(NvencEncoder* e, NeImport* im) {
    if (im->reg) g.fl.nvEncUnregisterResource(e->session, im->reg);
    if (im->res) g.cuGraphicsUnregisterResource(im->res);
    if (im->img) g.eglDestroyImageKHR(g.dpy, im->img);
    memset(im, 0, sizeof *im);
}

static void ne_free(NvencEncoder* e) {
    if (e->session) {
        g.cuCtxPush(e->cu);
        for (int i = 0; i < NE_IMPORT_CACHE; i++)
            ne_release_import(e, &e->imports[i]);
        if (e->bitstream)
            g.fl.nvEncDestroyBitstreamBuffer(e->session, e->bitstream);
        g.fl.nvEncDestroyEncoder(e->session);
        CUcontext dummy;
        g.cuCtxPop(&dummy);
    }
    if (e->cu) g.cuCtxDestroy(e->cu);
    free(e);
}

// The NVIDIA device's EGL display, initialized once for the process and
// deliberately never terminated (device displays are shared handles; a
// future NVIDIA engine view in this process gets the same one back).
static EGLDisplay ne_egl_display(void) {
    if (g.dpy != EGL_NO_DISPLAY && g.dpy != NULL) return g.dpy;
    EGLDeviceEXT devices[16];
    EGLint n = 0;
    if (!g.eglQueryDevicesEXT(16, devices, &n)) return EGL_NO_DISPLAY;
    for (EGLint i = 0; i < n; i++) {
        const char* ext =
            g.eglQueryDeviceStringEXT(devices[i], EGL_EXTENSIONS);
        if (!ext || !strstr(ext, "EGL_NV_device_cuda")) continue;
        EGLDisplay dpy = g.eglGetPlatformDisplayEXT(
            EGL_PLATFORM_DEVICE_EXT, devices[i], NULL);
        if (dpy == EGL_NO_DISPLAY) continue;
        if (!g.eglInitialize(dpy, NULL, NULL)) continue;
        g.dpy = dpy;
        return dpy;
    }
    return EGL_NO_DISPLAY;
}

// ─── probe ───────────────────────────────────────────────────────────────────

static void* ne_open_session(CUcontext cu) {
    NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS sp;
    memset(&sp, 0, sizeof sp);
    sp.version = NV_ENC_OPEN_ENCODE_SESSION_EX_PARAMS_VER;
    sp.deviceType = NV_ENC_DEVICE_TYPE_CUDA;
    sp.device = cu;
    sp.apiVersion = NVENCAPI_VERSION;
    void* session = NULL;
    if (g.fl.nvEncOpenEncodeSessionEx(&sp, &session) != NV_ENC_SUCCESS)
        return NULL;
    return session;
}

// Fill cfg/init for a session. Returns NV_ENC_SUCCESS or the failing status.
static NVENCSTATUS ne_init_encoder(void* session, NV_ENC_CONFIG* cfg,
                                   NV_ENC_INITIALIZE_PARAMS* ip,
                                   int w, int h, int fps, int qp) {
    NV_ENC_PRESET_CONFIG pc;
    memset(&pc, 0, sizeof pc);
    pc.version = NV_ENC_PRESET_CONFIG_VER;
    pc.presetCfg.version = NV_ENC_CONFIG_VER;
    NVENCSTATUS st = g.fl.nvEncGetEncodePresetConfigEx(
        session, NV_ENC_CODEC_H264_GUID, NV_ENC_PRESET_P4_GUID,
        NV_ENC_TUNING_INFO_HIGH_QUALITY, &pc);
    if (st != NV_ENC_SUCCESS) return st;
    *cfg = pc.presetCfg;

    // ve_send_rate_control's budget, verbatim.
    double bpp = 0.15 * (24.0 / (qp > 0 ? (double)qp : 24.0));
    double target = (double)w * (double)h * (double)fps * bpp;
    if (target < 4e6) target = 4e6;
    if (target > 30e6) target = 30e6;

    cfg->gopLength = (uint32_t)(fps * 2);
    cfg->frameIntervalP = 1;  // IPP, no B-frames — same as the VAAPI path
    cfg->rcParams.rateControlMode = NV_ENC_PARAMS_RC_VBR;
    cfg->rcParams.averageBitRate = (uint32_t)target;
    cfg->rcParams.maxBitRate = (uint32_t)(target * 1.5);
    cfg->encodeCodecConfig.h264Config.idrPeriod = (uint32_t)(fps * 2);
    cfg->encodeCodecConfig.h264Config.repeatSPSPPS = 1;

    memset(ip, 0, sizeof *ip);
    ip->version = NV_ENC_INITIALIZE_PARAMS_VER;
    ip->encodeGUID = NV_ENC_CODEC_H264_GUID;
    ip->presetGUID = NV_ENC_PRESET_P4_GUID;
    ip->tuningInfo = NV_ENC_TUNING_INFO_HIGH_QUALITY;
    ip->encodeWidth = (uint32_t)w;
    ip->encodeHeight = (uint32_t)h;
    ip->darWidth = (uint32_t)w;
    ip->darHeight = (uint32_t)h;
    ip->frameRateNum = (uint32_t)fps;
    ip->frameRateDen = 1;
    ip->enablePTD = 1;
    ip->encodeConfig = cfg;
    return g.fl.nvEncInitializeEncoder(session, ip);
}

int nvenc_encoder_probe(void) {
    // Fast negative before touching CUDA: no driver, no probe.
    if (access("/dev/nvidiactl", F_OK) != 0) return 0;
    if (!ne_load()) return 0;
    if (ne_egl_display() == EGL_NO_DISPLAY) return 0;

    CUdevice dev;
    CUcontext cu = NULL;
    if (g.cuDeviceGet(&dev, 0) != CUDA_SUCCESS) return 0;
    if (g.cuCtxCreate(&cu, 0, dev) != CUDA_SUCCESS) return 0;

    int ok = 0;
    void* session = ne_open_session(cu);
    if (session) {
        NV_ENC_CONFIG cfg;
        NV_ENC_INITIALIZE_PARAMS ip;
        ok = ne_init_encoder(session, &cfg, &ip, 256, 256, 30, 24) ==
             NV_ENC_SUCCESS;
        g.fl.nvEncDestroyEncoder(session);
    }
    CUcontext dummy;
    g.cuCtxPop(&dummy);
    g.cuCtxDestroy(cu);
    return ok;
}

// ─── open ────────────────────────────────────────────────────────────────────

// nvEncGetSequenceParams hands back Annex-B SPS+PPS (already
// emulation-escaped). The muxer wants them bare, so split on start codes.
static int ne_split_spspps(const uint8_t* buf, size_t len,
                           const uint8_t** sps, size_t* sps_len,
                           const uint8_t** pps, size_t* pps_len) {
    *sps = NULL;
    *pps = NULL;
    size_t i = 0;
    while (i + 4 < len) {
        size_t sc = 0;
        if (buf[i] == 0 && buf[i + 1] == 0 && buf[i + 2] == 1) sc = 3;
        else if (i + 4 < len && buf[i] == 0 && buf[i + 1] == 0 &&
                 buf[i + 2] == 0 && buf[i + 3] == 1) sc = 4;
        if (!sc) { i++; continue; }
        size_t start = i + sc;
        size_t end = len;
        for (size_t j = start; j + 3 < len; j++) {
            if (buf[j] == 0 && buf[j + 1] == 0 &&
                (buf[j + 2] == 1 || (j + 4 <= len && buf[j + 2] == 0 &&
                                     buf[j + 3] == 1))) {
                end = j;
                break;
            }
        }
        int type = buf[start] & 0x1f;
        if (type == 7) { *sps = buf + start; *sps_len = end - start; }
        if (type == 8) { *pps = buf + start; *pps_len = end - start; }
        i = end;
    }
    return *sps && *pps ? 0 : -1;
}

NvencEncoder* nvenc_encoder_open(int in_w, int in_h, int out_w, int out_h,
                                 int fps, int qp, const char* out_path) {
    if (!ne_load()) return NULL;
    if (ne_egl_display() == EGL_NO_DISPLAY) return NULL;
    if (out_w <= 0 || out_h <= 0 || (out_w & 1) || (out_h & 1)) return NULL;
    if (in_w < out_w || in_h < out_h) return NULL;

    NvencEncoder* e = calloc(1, sizeof *e);
    if (!e) return NULL;
    e->in_w = in_w;
    e->in_h = in_h;
    e->out_w = out_w;
    e->out_h = out_h;
    e->fps = fps;
    snprintf(e->path, sizeof e->path, "%s", out_path);

    CUdevice dev;
    if (g.cuDeviceGet(&dev, 0) != CUDA_SUCCESS ||
        g.cuCtxCreate(&e->cu, 0, dev) != CUDA_SUCCESS) {
        free(e);
        return NULL;
    }
    // cuCtxCreate leaves the context current here; keep it that way for
    // the rest of open and pop before returning — encode pushes it back.
    e->session = ne_open_session(e->cu);
    if (!e->session) goto fail;

    NV_ENC_CONFIG cfg;
    NV_ENC_INITIALIZE_PARAMS ip;
    NVENCSTATUS st = ne_init_encoder(e->session, &cfg, &ip,
                                     out_w, out_h, fps, qp);
    if (st != NV_ENC_SUCCESS) goto fail;

    NV_ENC_CREATE_BITSTREAM_BUFFER cbb;
    memset(&cbb, 0, sizeof cbb);
    cbb.version = NV_ENC_CREATE_BITSTREAM_BUFFER_VER;
    if (g.fl.nvEncCreateBitstreamBuffer(e->session, &cbb) != NV_ENC_SUCCESS)
        goto fail;
    e->bitstream = cbb.bitstreamBuffer;

    uint8_t hdr[512];
    uint32_t hdr_len = 0;
    NV_ENC_SEQUENCE_PARAM_PAYLOAD spp;
    memset(&spp, 0, sizeof spp);
    spp.version = NV_ENC_SEQUENCE_PARAM_PAYLOAD_VER;
    spp.inBufferSize = sizeof hdr;
    spp.spsppsBuffer = hdr;
    spp.outSPSPPSPayloadSize = &hdr_len;
    if (g.fl.nvEncGetSequenceParams(e->session, &spp) != NV_ENC_SUCCESS)
        goto fail;

    const uint8_t *sps, *pps;
    size_t sps_len, pps_len;
    if (ne_split_spspps(hdr, hdr_len, &sps, &sps_len, &pps, &pps_len) != 0)
        goto fail;

    e->mux = mp4_mux_open(out_path, out_w, out_h, NE_TIMESCALE,
                          sps, sps_len, pps, pps_len);
    if (!e->mux) goto fail;

    CUcontext dummy;
    g.cuCtxPop(&dummy);
    return e;

fail:
    {
        CUcontext dummy;
        g.cuCtxPop(&dummy);
    }
    // No file left behind on a failed open. The muxer is the last step, so
    // e->mux is never live here — but mp4_mux_open may have created the
    // file before failing its header write, and unlink of a name that was
    // never created is harmless.
    unlink(e->path);
    ne_free(e);
    return NULL;
}

// ─── encode ──────────────────────────────────────────────────────────────────

// Wrap the dma-buf in an EGLImage, map it into CUDA via graphics interop,
// and register the pitch-linear device pointer with NVENC — cached per
// underlying buffer. Context must be current. NULL on failure, e->err set.
static NeImport* ne_import(NvencEncoder* e, int fd, uint32_t stride,
                           uint32_t offset, uint32_t fourcc) {
    struct stat sb;
    if (fstat(fd, &sb) != 0) {
        ne_set_err(e, "fstat(dma-buf)", errno);
        return NULL;
    }
    for (int i = 0; i < NE_IMPORT_CACHE; i++) {
        NeImport* im = &e->imports[i];
        if (im->img && im->dev == (uint64_t)sb.st_dev &&
            im->ino == (uint64_t)sb.st_ino && im->stride == stride &&
            im->offset == offset) {
            return im;
        }
    }

    EGLint attrs[] = {
        EGL_WIDTH, e->out_w,
        EGL_HEIGHT, e->out_h,
        EGL_LINUX_DRM_FOURCC_EXT, (EGLint)fourcc,
        EGL_DMA_BUF_PLANE0_FD_EXT, fd,
        EGL_DMA_BUF_PLANE0_OFFSET_EXT, (EGLint)offset,
        EGL_DMA_BUF_PLANE0_PITCH_EXT, (EGLint)stride,
        EGL_NONE,
    };
    EGLImageKHR img = g.eglCreateImageKHR(g.dpy, EGL_NO_CONTEXT,
                                          EGL_LINUX_DMA_BUF_EXT, NULL, attrs);
    if (img == EGL_NO_IMAGE_KHR) {
        ne_set_err(e, "eglCreateImageKHR(dma-buf)", 0);
        return NULL;
    }

    ne_CUgraphicsResource res = NULL;
    CUresult cr = g.cuGraphicsEGLRegisterImage(&res, img, 0);
    if (cr != CUDA_SUCCESS) {
        g.eglDestroyImageKHR(g.dpy, img);
        ne_set_err(e, "cuGraphicsEGLRegisterImage", (int)cr);
        return NULL;
    }
    ne_CUeglFrame fr;
    memset(&fr, 0, sizeof fr);
    cr = g.cuGraphicsResourceGetMappedEglFrame(&fr, res, 0, 0);
    if (cr != CUDA_SUCCESS || fr.frameType != 1 /*PITCH*/ ||
        !fr.frame.pPitch[0]) {
        g.cuGraphicsUnregisterResource(res);
        g.eglDestroyImageKHR(g.dpy, img);
        ne_set_err(e, "cuGraphicsResourceGetMappedEglFrame", (int)cr);
        return NULL;
    }

    NV_ENC_REGISTER_RESOURCE rr;
    memset(&rr, 0, sizeof rr);
    rr.version = NV_ENC_REGISTER_RESOURCE_VER;
    rr.resourceType = NV_ENC_INPUT_RESOURCE_TYPE_CUDADEVICEPTR;
    rr.resourceToRegister = fr.frame.pPitch[0];
    rr.width = (uint32_t)e->out_w;
    rr.height = (uint32_t)e->out_h;
    rr.pitch = fr.pitch;
    rr.bufferFormat = NV_ENC_BUFFER_FORMAT_ABGR;  // R at byte 0, like AB24
    rr.bufferUsage = NV_ENC_INPUT_IMAGE;
    NVENCSTATUS st = g.fl.nvEncRegisterResource(e->session, &rr);
    if (st != NV_ENC_SUCCESS) {
        g.cuGraphicsUnregisterResource(res);
        g.eglDestroyImageKHR(g.dpy, img);
        ne_set_err(e, "nvEncRegisterResource", (int)st);
        return NULL;
    }

    NeImport* slot = &e->imports[e->import_next];
    e->import_next = (e->import_next + 1) % NE_IMPORT_CACHE;
    if (slot->img) ne_release_import(e, slot);
    slot->dev = (uint64_t)sb.st_dev;
    slot->ino = (uint64_t)sb.st_ino;
    slot->stride = stride;
    slot->offset = offset;
    slot->img = img;
    slot->res = res;
    slot->pitch = fr.pitch;
    slot->reg = rr.registeredResource;
    return slot;
}

int nvenc_encoder_encode(NvencEncoder* e, int fd, uint32_t stride,
                         uint32_t offset, uint32_t fourcc, uint64_t modifier,
                         uint64_t pts_us) {
    if (!e) return -1;
    if (fourcc != DRM_FORMAT_ABGR8888 && fourcc != DRM_FORMAT_XBGR8888) {
        ne_set_err(e, "unsupported fourcc", (int)fourcc);
        return -1;
    }
    if (modifier != DRM_FORMAT_MOD_LINEAR &&
        modifier != DRM_FORMAT_MOD_INVALID_) {
        ne_set_err(e, "non-linear modifier", (int)(modifier & 0xffff));
        return -1;
    }

    g.cuCtxPush(e->cu);
    NVENCSTATUS st;
    NV_ENC_INPUT_PTR mapped = NULL;

    NeImport* im = ne_import(e, fd, stride, offset, fourcc);
    if (!im) goto fail_pop;  // err already set

    // GPU-side handoff on one device: the producer's writes are ordered
    // ahead of the encode by the driver (same GPU, same channel domain) —
    // the same implicit contract the VAAPI path leans on.
    NV_ENC_MAP_INPUT_RESOURCE mir;
    memset(&mir, 0, sizeof mir);
    mir.version = NV_ENC_MAP_INPUT_RESOURCE_VER;
    mir.registeredResource = im->reg;
    st = g.fl.nvEncMapInputResource(e->session, &mir);
    if (st != NV_ENC_SUCCESS) {
        ne_set_err(e, "nvEncMapInputResource", (int)st);
        goto fail_pop;
    }
    mapped = mir.mappedResource;

    NV_ENC_PIC_PARAMS pp;
    memset(&pp, 0, sizeof pp);
    pp.version = NV_ENC_PIC_PARAMS_VER;
    pp.inputBuffer = mapped;
    pp.bufferFmt = mir.mappedBufferFmt;
    pp.inputWidth = (uint32_t)e->out_w;
    pp.inputHeight = (uint32_t)e->out_h;
    pp.inputPitch = im->pitch;
    pp.outputBitstream = e->bitstream;
    pp.pictureStruct = NV_ENC_PIC_STRUCT_FRAME;
    pp.inputTimeStamp = pts_us;
    st = g.fl.nvEncEncodePicture(e->session, &pp);
    if (st != NV_ENC_SUCCESS) {
        ne_set_err(e, "nvEncEncodePicture", (int)st);
        goto fail_pop;
    }

    NV_ENC_LOCK_BITSTREAM lb;
    memset(&lb, 0, sizeof lb);
    lb.version = NV_ENC_LOCK_BITSTREAM_VER;
    lb.outputBitstream = e->bitstream;
    st = g.fl.nvEncLockBitstream(e->session, &lb);
    if (st != NV_ENC_SUCCESS) {
        ne_set_err(e, "nvEncLockBitstream", (int)st);
        goto fail_pop;
    }

    if (e->frames == 0) e->first_pts = pts_us;
    uint64_t dts = pts_us - e->first_pts;
    int is_idr = lb.pictureType == NV_ENC_PIC_TYPE_IDR;
    int mux_rc = mp4_mux_write_sample(e->mux, lb.bitstreamBufferPtr,
                                      lb.bitstreamSizeInBytes, dts, is_idr);
    g.fl.nvEncUnlockBitstream(e->session, e->bitstream);
    g.fl.nvEncUnmapInputResource(e->session, mapped);
    mapped = NULL;
    if (mux_rc != 0) {
        snprintf(e->err, sizeof e->err, "mux: %s", mp4_mux_error(e->mux));
        goto fail_pop;
    }

    e->frames++;
    {
        CUcontext dummy;
        g.cuCtxPop(&dummy);
    }
    return 0;

fail_pop:
    if (mapped) g.fl.nvEncUnmapInputResource(e->session, mapped);
    {
        CUcontext dummy;
        g.cuCtxPop(&dummy);
    }
    return -1;
}

int nvenc_encoder_frame_count(NvencEncoder* e) { return e ? e->frames : 0; }

// ─── teardown ────────────────────────────────────────────────────────────────

int nvenc_encoder_finish(NvencEncoder* e) {
    if (!e) return -1;
    if (e->frames == 0) {
        ne_set_err(e, "no frames encoded", 0);
        return -1;
    }
    g.cuCtxPush(e->cu);
    NV_ENC_PIC_PARAMS eos;
    memset(&eos, 0, sizeof eos);
    eos.version = NV_ENC_PIC_PARAMS_VER;
    eos.encodePicFlags = NV_ENC_PIC_FLAG_EOS;
    (void)g.fl.nvEncEncodePicture(e->session, &eos);  // IPP: nothing pending
    CUcontext dummy;
    g.cuCtxPop(&dummy);

    if (mp4_mux_finish(e->mux) != 0) {
        snprintf(e->err, sizeof e->err, "mux finish: %s",
                 mp4_mux_error(e->mux));
        return -1;
    }
    e->mux = NULL;
    ne_free(e);
    return 0;
}

void nvenc_encoder_abort(NvencEncoder* e) {
    if (!e) return;
    if (e->mux) mp4_mux_abort(e->mux);
    unlink(e->path);
    ne_free(e);
}

const char* nvenc_encoder_error(NvencEncoder* e) {
    return e ? e->err : "no encoder";
}
