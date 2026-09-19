// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0
//
// See starling_room.h. Filament is created on the caller's EGL display
// with a context shared with the caller's; it runs on its own thread, so
// the caller's context is never made current anywhere else and nothing
// here touches the caller's GL state.

#include "starling_room.h"

#include <EGL/egl.h>

#include <backend/platforms/PlatformEGLHeadless.h>
#include <filament/Camera.h>
#include <filament/ColorGrading.h>
#include <filament/Engine.h>
#include <filament/IndirectLight.h>
#include <filament/LightManager.h>
#include <filament/Options.h>
#include <filament/RenderTarget.h>
#include <filament/Renderer.h>
#include <filament/Scene.h>
#include <filament/Skybox.h>
#include <filament/SwapChain.h>
#include <filament/Texture.h>
#include <filament/TransformManager.h>
#include <filament/View.h>
#include <filament/Viewport.h>
#include <gltfio/AssetLoader.h>
#include <gltfio/Animator.h>
#include <gltfio/FilamentInstance.h>
#include <gltfio/FilamentAsset.h>
#include <gltfio/MaterialProvider.h>
#include <gltfio/ResourceLoader.h>
#include <gltfio/TextureProvider.h>
#include <gltfio/materials/uberarchive.h>
#include <image/Ktx1Bundle.h>
#include <ktxreader/Ktx1Reader.h>
#include <math/mat3.h>
#include <math/mat4.h>
#include <math/vec3.h>
#include <filament/Box.h>
#include <filament/IndexBuffer.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/RenderableManager.h>
#include <filament/TextureSampler.h>
#include <filament/VertexBuffer.h>
#include <geometry/SurfaceOrientation.h>
#include <utils/EntityManager.h>
#include <unordered_map>

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>

using namespace filament;
using namespace filament::backend;
using namespace filament::math;

namespace {

/// Filament's headless EGL platform, pointed at the caller's display
/// instead of the default one — objects can only be shared between
/// contexts on the same display.
class StarlingPlatform final : public PlatformEGLHeadless {
public:
    explicit StarlingPlatform(EGLDisplay display) { setEglDisplay(display); }
};

bool readFile(const char* path, std::vector<uint8_t>& out) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) return false;
    auto n = f.tellg();
    out.resize(size_t(n));
    f.seekg(0);
    f.read(reinterpret_cast<char*>(out.data()), n);
    return bool(f);
}

double nowMs() {
    using namespace std::chrono;
    return duration<double, std::milli>(steady_clock::now().time_since_epoch()).count();
}

} // namespace

// The pane materials, compiled by matc at build time (build-room.sh).
static const uint8_t SCREEN_MAT[] = {
#include "screen.inc"
};
static const uint8_t FRAME_MAT[] = {
#include "frame.inc"
};
static const uint8_t GLOW_MAT[] = {
#include "glow.inc"
};
static const uint8_t LABEL_MAT[] = {
#include "label.inc"
};
static const uint8_t BLOCK_MAT[] = {
#include "block.inc"
};

/// A sphere in the scene: a planet, or the sun.
struct Orb {
    utils::Entity entity;
    MaterialInstance* mi = nullptr;
    bool glowing = false;
};

/// A billboard: a labelled quad turned toward the viewer every frame.
struct Label {
    utils::Entity entity;
    MaterialInstance* mi = nullptr;
    Texture* texture = nullptr;
    uint32_t glName = 0;
    int texW = 0, texH = 0;
    float3 centre{};
    float width = 0, height = 0;
    bool fixedYaw = false;
    float yaw = 0;
};

/// A block: a textured cube (an app's icon standing in the world).
struct Block {
    utils::Entity entity;
    MaterialInstance* mi = nullptr;
    Texture* texture = nullptr;
    uint32_t glName = 0;
    int texW = 0, texH = 0;
};

/// One window in the room: the client's picture on a quad, in a slab.
struct Pane {
    utils::Entity screen, frame;
    MaterialInstance* screenMi = nullptr;
    MaterialInstance* frameMi = nullptr;
    Texture* texture = nullptr;
    uint32_t glName = 0;
    int texW = 0, texH = 0;
    int styleGen = -1;      // which pane style its frame material carries
};

struct sr_room {
    StarlingPlatform* platform = nullptr;
    Engine* engine = nullptr;
    Renderer* renderer = nullptr;
    Scene* scene = nullptr;
    View* view = nullptr;
    Camera* camera = nullptr;
    utils::Entity cameraEntity;
    SwapChain* swapChain = nullptr;

    gltfio::MaterialProvider* materials = nullptr;
    gltfio::AssetLoader* loader = nullptr;
    gltfio::ResourceLoader* resources = nullptr;
    gltfio::TextureProvider* stb = nullptr;
    gltfio::FilamentAsset* asset = nullptr;
    gltfio::Animator* animator = nullptr; // owned by the asset
    double animationStart = 0;

    image::Ktx1Bundle* iblBundle = nullptr;
    image::Ktx1Bundle* skyBundle = nullptr;
    Texture* iblTexture = nullptr;
    Texture* skyTexture = nullptr;
    IndirectLight* ibl = nullptr;
    Skybox* skybox = nullptr;
    utils::Entity sun;
    bool haveSun = false;

    // Panes: shared unit geometry, two materials, one Pane per window.
    VertexBuffer* quadVb = nullptr;
    IndexBuffer* quadIb = nullptr;
    VertexBuffer* boxVb = nullptr;
    IndexBuffer* boxIb = nullptr;
    Material* screenMat = nullptr;
    Material* frameMat = nullptr;
    std::vector<float> boxVerts;          // pos(3) per vertex, kept alive for the upload
    std::vector<float4> boxTangents;
    // An unlit material's colour skips the exposure the lights are scaled
    // by and goes straight to the tone mapper, so 1.0 is already "white
    // before tone mapping": a screen reads bright against a sunlit room at
    // a little over half of that.
    float screenIntensity = 0.6f;
    std::unordered_map<int64_t, Pane> panes;
    // The frames' style: a plain slab, or a world's block tile repeated
    // over a thicker one (sr_room_set_pane_style). Bumping styleGen makes
    // every pane refresh its frame material on its next update.
    Texture* frameTexture = nullptr;
    Texture* frameBlank = nullptr;      // a 1x1 stand-in, so the sampler is never unset
    uint32_t frameGlName = 0;
    int frameTexW = 0, frameTexH = 0;
    float frameBlock = 0.25f;
    float paneMargin = 0.04f, paneDepth = 0.035f;
    int styleGen = 0;

    // Orbs and labels (the orrery), and the light at its hub.
    VertexBuffer* sphereVb = nullptr;
    IndexBuffer* sphereIb = nullptr;
    int sphereIndexCount = 0;
    std::vector<float> sphereVerts;
    std::vector<float4> sphereTangents;
    std::vector<uint16_t> sphereIdx;
    Material* glowMat = nullptr;
    Material* labelMat = nullptr;
    std::unordered_map<int64_t, Orb> orbs;
    std::unordered_map<int64_t, Label> labels;
    // Blocks: a unit cube with a picture on every face.
    VertexBuffer* cubeVb = nullptr;
    IndexBuffer* cubeIb = nullptr;
    Material* blockMat = nullptr;
    std::vector<float> cubeVerts;          // pos(3) uv(2) per vertex
    std::vector<float4> cubeTangents;
    std::vector<uint16_t> cubeIdx;
    std::unordered_map<int64_t, Block> blocks;
    utils::Entity pointLight;
    bool havePointLight = false;
    mat4f cameraModel;   // inverse of the view: where the viewer is, and which way

    Texture* output = nullptr;
    RenderTarget* target = nullptr;
    uint32_t outputName = 0;
    int width = 0, height = 0;
    int frames = 0;
};

extern "C" {

sr_room* sr_room_create(void* egl_display, void* shared_egl_context) {
    auto* r = new sr_room();
    r->platform = new StarlingPlatform(static_cast<EGLDisplay>(egl_display));
    r->engine = Engine::Builder()
            .backend(Engine::Backend::OPENGL)
            .platform(r->platform)
            .sharedContext(shared_egl_context)
            .build();
    if (!r->engine) {
        fprintf(stderr, "[room] Filament engine failed to start\n");
        delete r;
        return nullptr;
    }
    r->renderer = r->engine->createRenderer();
    r->scene = r->engine->createScene();
    r->view = r->engine->createView();
    r->cameraEntity = utils::EntityManager::get().create();
    r->camera = r->engine->createCamera(r->cameraEntity);
    // A swap chain is required by the frame API; on a GBM display there is
    // no pbuffer to back it, and the frame is rendered into our render
    // target instead, so the surface it lacks is never drawn to.
    r->swapChain = r->engine->createSwapChain(16, 16, 0);

    r->view->setScene(r->scene);
    r->view->setCamera(r->camera);
    // STARLING_ROOM_FX=lean drops the effects that cost the most at
    // 2560x1600 (multisampling, ambient occlusion, bloom); the shadows and
    // tone mapping stay. For measuring what the look is worth.
    const char* fx = getenv("STARLING_ROOM_FX");
    const bool lean = fx && strcmp(fx, "lean") == 0;
    r->view->setPostProcessingEnabled(true);
    r->view->setAntiAliasing(View::AntiAliasing::FXAA);
    MultiSampleAntiAliasingOptions msaa;
    msaa.enabled = !lean;
    msaa.sampleCount = 4;
    r->view->setMultiSampleAntiAliasingOptions(msaa);
    r->view->setShadowingEnabled(true);
    r->view->setShadowType(ShadowType::PCF);
    AmbientOcclusionOptions ao;
    ao.enabled = !lean;
    r->view->setAmbientOcclusionOptions(ao);
    BloomOptions bloom;
    bloom.enabled = !lean;
    bloom.strength = 0.06f;
    r->view->setBloomOptions(bloom);
    DynamicResolutionOptions dr;
    dr.enabled = false;
    r->view->setDynamicResolutionOptions(dr);
    r->view->setDithering(Dithering::TEMPORAL);

    Renderer::ClearOptions clear;
    clear.clearColor = { 0.0f, 0.0f, 0.0f, 1.0f };
    clear.clear = true;
    r->renderer->setClearOptions(clear);
    // Filament skips a frame it judges the GPU cannot finish in time; we
    // render on demand and wait, so there is never a frame to protect.
    Renderer::FrameRateOptions fr;
    fr.headRoomRatio = 0.0f;
    fr.interval = 1;
    r->renderer->setFrameRateOptions(fr);

    r->camera->setExposure(16.0f, 1.0f / 125.0f, 100.0f);
    if (const char* n = getenv("STARLING_ROOM_SCREEN")) r->screenIntensity = float(atof(n));
    return r;
}

int sr_room_load(sr_room* r, const char* glb_path, const char* ibl_ktx_path,
                 const char* skybox_ktx_path) {
    double t0 = nowMs();
    // A world need not have any geometry of its own (the orrery is only
    // a sky and what the shell puts in it): an empty path skips the asset.
    if (glb_path && *glb_path) {
        std::vector<uint8_t> glb;
        if (!readFile(glb_path, glb)) {
            fprintf(stderr, "[room] cannot read %s\n", glb_path);
            return -1;
        }
        r->materials = gltfio::createUbershaderProvider(
                r->engine, UBERARCHIVE_DEFAULT_DATA, UBERARCHIVE_DEFAULT_SIZE);
        gltfio::AssetConfiguration ac{};
        ac.engine = r->engine;
        ac.materials = r->materials;
        r->loader = gltfio::AssetLoader::create(ac);
        r->asset = r->loader->createAsset(glb.data(), uint32_t(glb.size()));
        if (!r->asset) {
            fprintf(stderr, "[room] %s is not a glTF the loader accepts\n", glb_path);
            return -2;
        }
        gltfio::ResourceConfiguration rc{};
        rc.engine = r->engine;
        rc.normalizeSkinningWeights = true;
        r->resources = new gltfio::ResourceLoader(rc);
        r->stb = gltfio::createStbProvider(r->engine);
        r->resources->addTextureProvider("image/png", r->stb);
        r->resources->addTextureProvider("image/jpeg", r->stb);
        if (!r->resources->loadResources(r->asset)) {
            fprintf(stderr, "[room] resources of %s failed to load\n", glb_path);
            return -3;
        }
        r->animator = r->asset->getInstance()->getAnimator();
        r->animationStart = nowMs();
        r->asset->releaseSourceData();
        r->scene->addEntities(r->asset->getRenderableEntities(),
                              r->asset->getRenderableEntityCount());
    }
    double t1 = nowMs();

    std::vector<uint8_t> ibl, sky;
    if (!readFile(ibl_ktx_path, ibl) || !readFile(skybox_ktx_path, sky)) {
        fprintf(stderr, "[room] cannot read the sky (%s, %s)\n", ibl_ktx_path, skybox_ktx_path);
        return -4;
    }
    r->iblBundle = new image::Ktx1Bundle(ibl.data(), uint32_t(ibl.size()));
    r->skyBundle = new image::Ktx1Bundle(sky.data(), uint32_t(sky.size()));
    r->iblTexture = ktxreader::Ktx1Reader::createTexture(r->engine, *r->iblBundle, false,
                                                         nullptr, nullptr);
    r->skyTexture = ktxreader::Ktx1Reader::createTexture(r->engine, *r->skyBundle, false,
                                                         nullptr, nullptr);
    float3 sh[9];
    if (!r->iblBundle->getSphericalHarmonics(sh)) {
        fprintf(stderr, "[room] %s carries no spherical harmonics (cmgen --format=ktx writes them)\n",
                ibl_ktx_path);
        return -5;
    }
    r->ibl = IndirectLight::Builder()
            .reflections(r->iblTexture)
            .irradiance(3, sh)
            .intensity(30000.0f)
            .build(*r->engine);
    r->scene->setIndirectLight(r->ibl);
    r->skybox = Skybox::Builder().environment(r->skyTexture).showSun(false).build(*r->engine);
    r->scene->setSkybox(r->skybox);
    fprintf(stderr, "[room] loaded %s: %zu renderables in %.0f ms, sky in %.0f ms\n",
            glb_path, r->asset ? r->asset->getRenderableEntityCount() : 0, t1 - t0, nowMs() - t1);
    return 0;
}

void sr_room_set_light(sr_room* r, const float sun_dir[3], const float sun_colour[3],
                       float sun_lux, float ibl_lux) {
    if (r->ibl) r->ibl->setIntensity(ibl_lux);
    if (r->haveSun) {
        r->scene->remove(r->sun);
        r->engine->getLightManager().destroy(r->sun);
        utils::EntityManager::get().destroy(r->sun);
        r->haveSun = false;
    }
    if (sun_lux <= 0) return;
    r->sun = utils::EntityManager::get().create();
    // Filament's direction is the way the light TRAVELS.
    float3 d = normalize(float3{ -sun_dir[0], -sun_dir[1], -sun_dir[2] });
    // The shadow map covers the view out to shadowFar; left at the
    // camera's far plane (4 km, for the sky) it spreads 1024 texels over
    // kilometres and every edge in the room is a staircase.
    LightManager::ShadowOptions shadows;
    shadows.mapSize = 2048;
    shadows.shadowCascades = 3;
    shadows.shadowFar = 25.0f;
    LightManager::Builder(LightManager::Type::SUN)
            .color({ sun_colour[0], sun_colour[1], sun_colour[2] })
            .intensity(sun_lux)
            .direction(d)
            .sunAngularRadius(1.9f)
            .castShadows(true)
            .shadowOptions(shadows)
            .build(*r->engine, r->sun);
    r->scene->addEntity(r->sun);
    r->haveSun = true;
}

void sr_room_set_exposure(sr_room* r, float aperture, float shutter, float iso) {
    r->camera->setExposure(aperture, shutter, iso);
}

int sr_room_set_output(sr_room* r, uint32_t gl_texture, int width, int height) {
    if (r->output && r->outputName == gl_texture && r->width == width && r->height == height) {
        return 0;
    }
    if (r->target) { r->engine->destroy(r->target); r->target = nullptr; }
    if (r->output) { r->engine->destroy(r->output); r->output = nullptr; }
    r->output = Texture::Builder()
            .width(uint32_t(width))
            .height(uint32_t(height))
            .levels(1)
            .sampler(Texture::Sampler::SAMPLER_2D)
            .format(Texture::InternalFormat::RGBA8)
            .usage(Texture::Usage::COLOR_ATTACHMENT | Texture::Usage::SAMPLEABLE)
            .import(intptr_t(gl_texture))
            .build(*r->engine);
    r->target = RenderTarget::Builder()
            .texture(RenderTarget::AttachmentPoint::COLOR, r->output)
            .build(*r->engine);
    r->view->setRenderTarget(r->target);
    r->view->setViewport({ 0, 0, uint32_t(width), uint32_t(height) });
    r->outputName = gl_texture;
    r->width = width;
    r->height = height;
    return r->output && r->target ? 0 : -1;
}

void sr_room_set_camera(sr_room* r, const float view[16], const float proj[16],
                        float near_plane, float far_plane) {
    mat4f v, p;
    memcpy(&v, view, sizeof(v));
    memcpy(&p, proj, sizeof(p));
    // No y flip: Filament's GL backend writes a render-target texture the
    // way raw GL does, clip y = -1 in row 0, and the engine shows row 0 at
    // the bottom of the screen. (A flip was added once on the word of a
    // test tool that wrote its picture bottom row first; the desktop
    // showed the room upside down. Measure on the desktop, not the tool.)
    r->camera->setCustomProjection(mat4(p), double(near_plane), double(far_plane));
    r->cameraModel = inverse(v);
    r->camera->setModelMatrix(r->cameraModel);
}

int sr_room_render(sr_room* r) {
    if (!r->target) return -1;
    double t0 = nowMs();
    // One animation clock for the shared scene, never one per monitor.
    // Independent clips loop at their own duration; static worlds cost nothing.
    if (r->animator) {
        const double seconds = (t0 - r->animationStart) / 1000.0;
        for (size_t i = 0; i < r->animator->getAnimationCount(); ++i) {
            const float duration = r->animator->getAnimationDuration(i);
            if (duration > 0) r->animator->applyAnimation(i, float(fmod(seconds, duration)));
        }
    }
    if (!r->labels.empty()) {
        // A label wears the viewer's own rotation, so its face is toward
        // the viewer wherever the viewer stands.
        auto& tcm = r->engine->getTransformManager();
        mat4f rot = r->cameraModel;
        rot[3] = float4{ 0, 0, 0, 1 };
        for (auto& kv : r->labels) {
            Label& l = kv.second;
            const mat4f facing = l.fixedYaw ? mat4f::rotation(l.yaw, float3{ 0, 1, 0 }) : rot;
            tcm.setTransform(tcm.getInstance(l.entity),
                    mat4f::translation(l.centre) * facing
                    * mat4f::scaling(float3{ l.width, l.height, 1.0f }));
        }
    }
    if (r->renderer->beginFrame(r->swapChain)) {
        r->renderer->render(r->view);
        r->renderer->endFrame();
    } else {
        fprintf(stderr, "[room] beginFrame declined\n");
    }
    r->engine->flushAndWait();
    if (r->frames < 3 || (r->frames % 300) == 0) {
        fprintf(stderr, "[room] frame %d: %.1f ms\n", r->frames, nowMs() - t0);
    }
    r->frames++;
    return 0;
}

void sr_room_equirect_direction(float u, float v, float out_dir[3]) {
    // cmgen's equirectangular mapping (CubemapUtils::toRectilinear, inverted):
    // u = (atan2(x, z) / pi + 1) / 2, v = (1 - asin(y) * 2 / pi) / 2.
    const float phi = (u * 2.0f - 1.0f) * float(M_PI);
    const float lat = (1.0f - v * 2.0f) * float(M_PI) / 2.0f;
    const float cl = cosf(lat);
    out_dir[0] = cl * sinf(phi);
    out_dir[1] = sinf(lat);
    out_dir[2] = cl * cosf(phi);
}

} // extern "C"

namespace {

// A unit quad in the xy plane facing +z, uv (0,0) at the bottom left —
// GL's texel row 0 — and a unit box, both scaled into place per pane by
// the transform component.
const float kQuad[] = {
    -0.5f, -0.5f, 0.0f, 0.0f, 0.0f,
     0.5f, -0.5f, 0.0f, 1.0f, 0.0f,
     0.5f,  0.5f, 0.0f, 1.0f, 1.0f,
    -0.5f,  0.5f, 0.0f, 0.0f, 1.0f,
};
const uint16_t kQuadIdx[] = { 0, 1, 2, 0, 2, 3 };

bool ensurePaneGeometry(sr_room* r) {
    if (r->quadVb) return true;
    Engine& e = *r->engine;
    r->screenMat = Material::Builder().package(SCREEN_MAT, sizeof(SCREEN_MAT)).build(e);
    r->frameMat = Material::Builder().package(FRAME_MAT, sizeof(FRAME_MAT)).build(e);
    if (!r->screenMat || !r->frameMat) {
        fprintf(stderr, "[room] pane materials failed to load\n");
        return false;
    }
    r->frameBlank = Texture::Builder()
            .width(1).height(1).levels(1).sampler(Texture::Sampler::SAMPLER_2D)
            .format(Texture::InternalFormat::RGBA8).build(e);
    static const uint8_t white[4] = { 255, 255, 255, 255 };
    r->frameBlank->setImage(e, 0, Texture::PixelBufferDescriptor(
            white, sizeof(white), Texture::Format::RGBA, Texture::Type::UBYTE));
    r->quadVb = VertexBuffer::Builder()
            .vertexCount(4).bufferCount(1)
            .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, 0, 20)
            .attribute(VertexAttribute::UV0, 0, VertexBuffer::AttributeType::FLOAT2, 12, 20)
            .build(e);
    r->quadVb->setBufferAt(e, 0, VertexBuffer::BufferDescriptor(kQuad, sizeof(kQuad)));
    r->quadIb = IndexBuffer::Builder().indexCount(6)
            .bufferType(IndexBuffer::IndexType::USHORT).build(e);
    r->quadIb->setBuffer(e, IndexBuffer::BufferDescriptor(kQuadIdx, sizeof(kQuadIdx)));

    // Six faces, four vertices each, wound counter-clockwise seen from
    // outside; a lit material wants its normals as tangent frames.
    const float3 faces[6][3] = {
        { { 0, 0, 1 }, { 1, 0, 0 }, { 0, 1, 0 } },
        { { 0, 0, -1 }, { -1, 0, 0 }, { 0, 1, 0 } },
        { { 1, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 } },
        { { -1, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 } },
        { { 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, -1 } },
        { { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 } },
    };
    std::vector<float3> normals;
    std::vector<uint16_t> idx;
    for (int f = 0; f < 6; f++) {
        const float3 n = faces[f][0], u = faces[f][1], v = faces[f][2];
        const float3 c = n * 0.5f;
        const float3 corners[4] = { c - u * 0.5f - v * 0.5f, c + u * 0.5f - v * 0.5f,
                                    c + u * 0.5f + v * 0.5f, c - u * 0.5f + v * 0.5f };
        const uint16_t b = uint16_t(f * 4);
        for (const float3& p : corners) {
            r->boxVerts.push_back(p.x); r->boxVerts.push_back(p.y); r->boxVerts.push_back(p.z);
            normals.push_back(n);
        }
        const uint16_t tri[6] = { b, uint16_t(b + 1), uint16_t(b + 2), b, uint16_t(b + 2), uint16_t(b + 3) };
        idx.insert(idx.end(), tri, tri + 6);
    }
    r->boxTangents.resize(24);
    auto* orientation = geometry::SurfaceOrientation::Builder()
            .vertexCount(24).normals(normals.data()).build();
    orientation->getQuats(reinterpret_cast<quatf*>(r->boxTangents.data()), 24);
    delete orientation;
    r->boxVb = VertexBuffer::Builder()
            .vertexCount(24).bufferCount(2)
            .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, 0, 12)
            .attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::FLOAT4, 0, 16)
            .build(e);
    r->boxVb->setBufferAt(e, 0, VertexBuffer::BufferDescriptor(
            r->boxVerts.data(), r->boxVerts.size() * sizeof(float)));
    r->boxVb->setBufferAt(e, 1, VertexBuffer::BufferDescriptor(
            r->boxTangents.data(), r->boxTangents.size() * sizeof(float4)));
    static uint16_t boxIdx[36];
    memcpy(boxIdx, idx.data(), sizeof(boxIdx));
    r->boxIb = IndexBuffer::Builder().indexCount(36)
            .bufferType(IndexBuffer::IndexType::USHORT).build(e);
    r->boxIb->setBuffer(e, IndexBuffer::BufferDescriptor(boxIdx, sizeof(boxIdx)));
    return true;
}

void destroyBlock(sr_room* r, Block& b) {
    Engine& e = *r->engine;
    r->scene->remove(b.entity);
    e.destroy(b.entity);
    utils::EntityManager::get().destroy(b.entity);
    if (b.mi) e.destroy(b.mi);
    if (b.texture) e.destroy(b.texture);
    b = Block{};
}

/// A unit cube with a picture on every face: positions and UVs (each
/// face's picture upright as seen from outside), and tangent frames for
/// the lit material.
bool ensureBlockGeometry(sr_room* r) {
    if (r->cubeVb) return true;
    if (!ensurePaneGeometry(r)) return false;
    Engine& e = *r->engine;
    r->blockMat = Material::Builder().package(BLOCK_MAT, sizeof(BLOCK_MAT)).build(e);
    if (!r->blockMat) {
        fprintf(stderr, "[room] block material failed to load\n");
        return false;
    }
    const float3 faces[6][3] = {
        { { 0, 0, 1 }, { 1, 0, 0 }, { 0, 1, 0 } },
        { { 0, 0, -1 }, { -1, 0, 0 }, { 0, 1, 0 } },
        { { 1, 0, 0 }, { 0, 0, -1 }, { 0, 1, 0 } },
        { { -1, 0, 0 }, { 0, 0, 1 }, { 0, 1, 0 } },
        { { 0, 1, 0 }, { 1, 0, 0 }, { 0, 0, -1 } },
        { { 0, -1, 0 }, { 1, 0, 0 }, { 0, 0, 1 } },
    };
    // One rule for every face, the top included: (0,0) at the corner
    // that is bottom-left seen from outside — for the top, seen from in
    // front and above, the front-left — and a word on it reads from the
    // front. (Turning the top's picture "to fix it" was a misreading of
    // a screenshot; it was right.)
    const float uvs[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
    std::vector<float3> normals;
    for (int f = 0; f < 6; f++) {
        const float3 n = faces[f][0], u = faces[f][1], v = faces[f][2];
        const float3 c = n * 0.5f;
        const float3 corners[4] = { c - u * 0.5f - v * 0.5f, c + u * 0.5f - v * 0.5f,
                                    c + u * 0.5f + v * 0.5f, c - u * 0.5f + v * 0.5f };
        const uint16_t b = uint16_t(f * 4);
        for (int i = 0; i < 4; i++) {
            r->cubeVerts.insert(r->cubeVerts.end(),
                    { corners[i].x, corners[i].y, corners[i].z, uvs[i][0], uvs[i][1] });
            normals.push_back(n);
        }
        r->cubeIdx.insert(r->cubeIdx.end(), { b, uint16_t(b + 1), uint16_t(b + 2), b, uint16_t(b + 2), uint16_t(b + 3) });
    }
    r->cubeTangents.resize(24);
    auto* orientation = geometry::SurfaceOrientation::Builder()
            .vertexCount(24).normals(normals.data()).build();
    orientation->getQuats(reinterpret_cast<quatf*>(r->cubeTangents.data()), 24);
    delete orientation;
    r->cubeVb = VertexBuffer::Builder()
            .vertexCount(24).bufferCount(2)
            .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, 0, 20)
            .attribute(VertexAttribute::UV0, 0, VertexBuffer::AttributeType::FLOAT2, 12, 20)
            .attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::FLOAT4, 0, 16)
            .build(e);
    r->cubeVb->setBufferAt(e, 0, VertexBuffer::BufferDescriptor(
            r->cubeVerts.data(), r->cubeVerts.size() * sizeof(float)));
    r->cubeVb->setBufferAt(e, 1, VertexBuffer::BufferDescriptor(
            r->cubeTangents.data(), r->cubeTangents.size() * sizeof(float4)));
    r->cubeIb = IndexBuffer::Builder().indexCount(36)
            .bufferType(IndexBuffer::IndexType::USHORT).build(e);
    r->cubeIb->setBuffer(e, IndexBuffer::BufferDescriptor(
            r->cubeIdx.data(), r->cubeIdx.size() * sizeof(uint16_t)));
    return true;
}

void destroyPane(sr_room* r, Pane& p) {
    Engine& e = *r->engine;
    r->scene->remove(p.screen);
    r->scene->remove(p.frame);
    e.destroy(p.screen);
    e.destroy(p.frame);
    utils::EntityManager::get().destroy(p.screen);
    utils::EntityManager::get().destroy(p.frame);
    if (p.screenMi) e.destroy(p.screenMi);
    if (p.frameMi) e.destroy(p.frameMi);
    if (p.texture) e.destroy(p.texture);
    p = Pane{};
}

} // namespace

extern "C" {

int sr_room_set_pane(sr_room* r, int64_t id, const float centre[3], float yaw,
                     float width, float height, float content_dy,
                     float content_w, float content_h,
                     uint32_t gl_texture, int tex_w, int tex_h,
                     int flip_y, int focused) {
    if (!ensurePaneGeometry(r)) return -1;
    Engine& e = *r->engine;
    auto& tcm = e.getTransformManager();
    Pane& p = r->panes[id];
    if (p.screen.isNull()) {
        auto& em = utils::EntityManager::get();
        p.screen = em.create();
        p.frame = em.create();
        p.screenMi = r->screenMat->createInstance();
        p.frameMi = r->frameMat->createInstance();
        p.frameMi->setParameter("baseColor", float3{ 0.20f, 0.14f, 0.09f });
        p.frameMi->setParameter("roughness", 0.55f);
        p.frameMi->setParameter("useMap", 0.0f);
        p.frameMi->setParameter("block", 0.25f);
        p.frameMi->setParameter("frameMap", r->frameBlank, TextureSampler());
        RenderableManager::Builder(1)
                .boundingBox({ { -0.5f, -0.5f, -0.5f }, { 0.5f, 0.5f, 0.5f } })
                .material(0, p.screenMi)
                .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, r->quadVb, r->quadIb, 0, 6)
                .culling(true).castShadows(false).receiveShadows(false)
                .build(e, p.screen);
        RenderableManager::Builder(1)
                .boundingBox({ { -0.5f, -0.5f, -0.5f }, { 0.5f, 0.5f, 0.5f } })
                .material(0, p.frameMi)
                .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, r->boxVb, r->boxIb, 0, 36)
                .culling(true).castShadows(true).receiveShadows(true)
                .build(e, p.frame);
        tcm.create(p.screen);
        tcm.create(p.frame);
        r->scene->addEntity(p.screen);
        r->scene->addEntity(p.frame);
    }
    if (gl_texture != p.glName || tex_w != p.texW || tex_h != p.texH) {
        if (p.texture) e.destroy(p.texture);
        p.texture = Texture::Builder()
                .width(uint32_t(std::max(tex_w, 1))).height(uint32_t(std::max(tex_h, 1)))
                .levels(1).sampler(Texture::Sampler::SAMPLER_2D)
                .format(Texture::InternalFormat::RGBA8)
                .usage(Texture::Usage::SAMPLEABLE)
                .import(intptr_t(gl_texture))
                .build(e);
        p.glName = gl_texture; p.texW = tex_w; p.texH = tex_h;
        TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR);
        sampler.setWrapModeS(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        sampler.setWrapModeT(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        p.screenMi->setParameter("content", p.texture, sampler);
    }
    p.screenMi->setParameter("flipY", flip_y ? 1.0f : 0.0f);
    p.screenMi->setParameter("intensity", r->screenIntensity);
    if (p.styleGen != r->styleGen) {
        p.styleGen = r->styleGen;
        if (r->frameTexture) {
            // A world's block: nearest, so the pixels stay pixels, and
            // repeated, so the slab is as many blocks as it is long.
            TextureSampler sampler(TextureSampler::MinFilter::NEAREST, TextureSampler::MagFilter::NEAREST);
            sampler.setWrapModeS(TextureSampler::WrapMode::REPEAT);
            sampler.setWrapModeT(TextureSampler::WrapMode::REPEAT);
            p.frameMi->setParameter("frameMap", r->frameTexture, sampler);
            p.frameMi->setParameter("block", r->frameBlock);
            p.frameMi->setParameter("roughness", 0.9f);
        } else {
            p.frameMi->setParameter("frameMap", r->frameBlank, TextureSampler());
            p.frameMi->setParameter("roughness", 0.55f);
        }
        p.frameMi->setParameter("useMap", r->frameTexture ? 1.0f : 0.0f);
    }
    if (r->frameTexture) {
        // The tile carries the colour; focus is a brightness.
        p.frameMi->setParameter("baseColor", focused ? float3{ 1.0f, 1.0f, 1.0f }
                                                     : float3{ 0.72f, 0.72f, 0.72f });
    } else {
        p.frameMi->setParameter("baseColor", focused ? float3{ 0.30f, 0.21f, 0.13f }
                                                     : float3{ 0.20f, 0.14f, 0.09f });
    }

    // The slab: a margin round the window and some depth, its front face
    // on the pane's plane and its body toward the wall. The picture floats
    // a hair in front of the slab so they never fight.
    const float margin = r->paneMargin, depth = r->paneDepth;
    const mat4f place = mat4f::translation(float3{ centre[0], centre[1], centre[2] })
            * mat4f::rotation(yaw, float3{ 0, 1, 0 });
    tcm.setTransform(tcm.getInstance(p.frame),
            place * mat4f::translation(float3{ 0, 0, -depth / 2 })
                  * mat4f::scaling(float3{ width + 2 * margin, height + 2 * margin, depth }));
    tcm.setTransform(tcm.getInstance(p.screen),
            place * mat4f::translation(float3{ 0, content_dy, 0.003f })
                  * mat4f::scaling(float3{ content_w, content_h, 1.0f }));
    return 0;
}

void sr_room_remove_pane(sr_room* r, int64_t id) {
    auto it = r->panes.find(id);
    if (it == r->panes.end()) return;
    destroyPane(r, it->second);
    r->panes.erase(it);
}

void sr_room_set_pane_style(sr_room* r, uint32_t gl_texture, int tex_w, int tex_h,
                            float block, float margin, float depth) {
    Engine& e = *r->engine;
    if (gl_texture != r->frameGlName || tex_w != r->frameTexW || tex_h != r->frameTexH) {
        // Every pane's material instance holds the old texture until its
        // next update; the engine keeps it alive until then.
        if (r->frameTexture) e.destroy(r->frameTexture);
        r->frameTexture = nullptr;
        r->frameGlName = gl_texture; r->frameTexW = tex_w; r->frameTexH = tex_h;
        if (gl_texture) {
            r->frameTexture = Texture::Builder()
                    .width(uint32_t(std::max(tex_w, 1))).height(uint32_t(std::max(tex_h, 1)))
                    .levels(1).sampler(Texture::Sampler::SAMPLER_2D)
                    .format(Texture::InternalFormat::RGBA8)
                    .usage(Texture::Usage::SAMPLEABLE)
                    .import(intptr_t(gl_texture))
                    .build(e);
        }
        r->styleGen++;
    }
    if (gl_texture) {
        r->frameBlock = block > 0 ? block : 0.25f;
        r->paneMargin = margin;
        r->paneDepth = depth;
    } else {
        r->paneMargin = 0.04f;
        r->paneDepth = 0.035f;
    }
}

void sr_room_set_point_light(sr_room* r, const float pos[3], const float colour[3],
                             float candela) {
    Engine& e = *r->engine;
    if (r->havePointLight) {
        r->scene->remove(r->pointLight);
        e.getLightManager().destroy(r->pointLight);
        utils::EntityManager::get().destroy(r->pointLight);
        r->havePointLight = false;
    }
    if (candela <= 0) return;
    r->pointLight = utils::EntityManager::get().create();
    LightManager::Builder(LightManager::Type::POINT)
            .position({ pos[0], pos[1], pos[2] })
            .color({ colour[0], colour[1], colour[2] })
            .intensityCandela(candela)
            .falloff(40.0f)
            .castShadows(false)
            .build(e, r->pointLight);
    r->scene->addEntity(r->pointLight);
    r->havePointLight = true;
}

} // extern "C"

namespace {

bool ensureOrbGeometry(sr_room* r) {
    if (r->sphereVb) return true;
    if (!ensurePaneGeometry(r)) return false;
    Engine& e = *r->engine;
    r->glowMat = Material::Builder().package(GLOW_MAT, sizeof(GLOW_MAT)).build(e);
    r->labelMat = Material::Builder().package(LABEL_MAT, sizeof(LABEL_MAT)).build(e);
    if (!r->glowMat || !r->labelMat) {
        fprintf(stderr, "[room] orb materials failed to load\n");
        return false;
    }
    // A unit sphere: latitude rings and longitude lines, normals radial.
    const int stacks = 18, slices = 36;
    std::vector<float3> normals;
    for (int i = 0; i <= stacks; i++) {
        const float v = float(i) / stacks, phi = v * float(M_PI);
        for (int j = 0; j <= slices; j++) {
            const float u = float(j) / slices, theta = u * 2.0f * float(M_PI);
            const float3 n{ sinf(phi) * cosf(theta), cosf(phi), sinf(phi) * sinf(theta) };
            r->sphereVerts.push_back(n.x * 0.5f);
            r->sphereVerts.push_back(n.y * 0.5f);
            r->sphereVerts.push_back(n.z * 0.5f);
            normals.push_back(n);
        }
    }
    for (int i = 0; i < stacks; i++) {
        for (int j = 0; j < slices; j++) {
            const uint16_t a = uint16_t(i * (slices + 1) + j), b = uint16_t(a + slices + 1);
            // Counter-clockwise seen from outside.
            r->sphereIdx.insert(r->sphereIdx.end(), { a, uint16_t(a + 1), b, uint16_t(a + 1), uint16_t(b + 1), b });
        }
    }
    const size_t n = normals.size();
    r->sphereTangents.resize(n);
    auto* orientation = geometry::SurfaceOrientation::Builder()
            .vertexCount(n).normals(normals.data()).build();
    orientation->getQuats(reinterpret_cast<quatf*>(r->sphereTangents.data()), n);
    delete orientation;
    r->sphereVb = VertexBuffer::Builder()
            .vertexCount(uint32_t(n)).bufferCount(2)
            .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, 0, 12)
            .attribute(VertexAttribute::TANGENTS, 1, VertexBuffer::AttributeType::FLOAT4, 0, 16)
            .build(e);
    r->sphereVb->setBufferAt(e, 0, VertexBuffer::BufferDescriptor(
            r->sphereVerts.data(), r->sphereVerts.size() * sizeof(float)));
    r->sphereVb->setBufferAt(e, 1, VertexBuffer::BufferDescriptor(
            r->sphereTangents.data(), r->sphereTangents.size() * sizeof(float4)));
    r->sphereIndexCount = int(r->sphereIdx.size());
    r->sphereIb = IndexBuffer::Builder().indexCount(uint32_t(r->sphereIdx.size()))
            .bufferType(IndexBuffer::IndexType::USHORT).build(e);
    r->sphereIb->setBuffer(e, IndexBuffer::BufferDescriptor(
            r->sphereIdx.data(), r->sphereIdx.size() * sizeof(uint16_t)));
    return true;
}

void destroyOrb(sr_room* r, Orb& o) {
    r->scene->remove(o.entity);
    r->engine->destroy(o.entity);
    utils::EntityManager::get().destroy(o.entity);
    if (o.mi) r->engine->destroy(o.mi);
    o = Orb{};
}

void destroyLabel(sr_room* r, Label& l) {
    r->scene->remove(l.entity);
    r->engine->destroy(l.entity);
    utils::EntityManager::get().destroy(l.entity);
    if (l.mi) r->engine->destroy(l.mi);
    if (l.texture) r->engine->destroy(l.texture);
    l = Label{};
}

} // namespace

extern "C" {

int sr_room_set_orb(sr_room* r, int64_t id, const float centre[3], float radius,
                    const float colour[3], float glow) {
    if (!ensureOrbGeometry(r)) return -1;
    Engine& e = *r->engine;
    auto& tcm = e.getTransformManager();
    Orb& o = r->orbs[id];
    const bool glowing = glow > 0;
    if (!o.entity.isNull() && o.glowing != glowing) destroyOrb(r, o);
    if (o.entity.isNull()) {
        o.entity = utils::EntityManager::get().create();
        o.glowing = glowing;
        o.mi = (glowing ? r->glowMat : r->frameMat)->createInstance();
        RenderableManager::Builder(1)
                .boundingBox({ { -0.5f, -0.5f, -0.5f }, { 0.5f, 0.5f, 0.5f } })
                .material(0, o.mi)
                .geometry(0, RenderableManager::PrimitiveType::TRIANGLES,
                          r->sphereVb, r->sphereIb, 0, size_t(r->sphereIndexCount))
                .culling(true).castShadows(!glowing).receiveShadows(!glowing)
                .build(e, o.entity);
        tcm.create(o.entity);
        r->scene->addEntity(o.entity);
    }
    if (glowing) {
        o.mi->setParameter("colour", float3{ colour[0], colour[1], colour[2] });
        o.mi->setParameter("intensity", glow);
    } else {
        o.mi->setParameter("baseColor", float3{ colour[0], colour[1], colour[2] });
        o.mi->setParameter("roughness", 0.45f);
    }
    tcm.setTransform(tcm.getInstance(o.entity),
            mat4f::translation(float3{ centre[0], centre[1], centre[2] })
            * mat4f::scaling(float3{ radius * 2, radius * 2, radius * 2 }));
    return 0;
}

void sr_room_remove_orb(sr_room* r, int64_t id) {
    auto it = r->orbs.find(id);
    if (it == r->orbs.end()) return;
    destroyOrb(r, it->second);
    r->orbs.erase(it);
}

int sr_room_set_label(sr_room* r, int64_t id, const float centre[3],
                      float width, float height, float yaw,
                      uint32_t gl_texture, int tex_w, int tex_h) {
    if (!ensureOrbGeometry(r)) return -1;
    Engine& e = *r->engine;
    auto& tcm = e.getTransformManager();
    Label& l = r->labels[id];
    if (l.entity.isNull()) {
        l.entity = utils::EntityManager::get().create();
        l.mi = r->labelMat->createInstance();
        l.mi->setParameter("intensity", 1.0f);
        RenderableManager::Builder(1)
                .boundingBox({ { -0.5f, -0.5f, -0.5f }, { 0.5f, 0.5f, 0.5f } })
                .material(0, l.mi)
                .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, r->quadVb, r->quadIb, 0, 6)
                .culling(false).castShadows(false).receiveShadows(false)
                .build(e, l.entity);
        tcm.create(l.entity);
        r->scene->addEntity(l.entity);
    }
    if (gl_texture != l.glName || tex_w != l.texW || tex_h != l.texH) {
        if (l.texture) e.destroy(l.texture);
        l.texture = Texture::Builder()
                .width(uint32_t(std::max(tex_w, 1))).height(uint32_t(std::max(tex_h, 1)))
                .levels(1).sampler(Texture::Sampler::SAMPLER_2D)
                .format(Texture::InternalFormat::RGBA8)
                .usage(Texture::Usage::SAMPLEABLE)
                .import(intptr_t(gl_texture))
                .build(e);
        l.glName = gl_texture; l.texW = tex_w; l.texH = tex_h;
        TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR);
        sampler.setWrapModeS(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        sampler.setWrapModeT(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        l.mi->setParameter("image", l.texture, sampler);
    }
    l.centre = float3{ centre[0], centre[1], centre[2] };
    l.width = width; l.height = height;
    l.fixedYaw = !std::isnan(yaw);
    l.yaw = l.fixedYaw ? yaw : 0.0f;
    return 0;
}

void sr_room_remove_label(sr_room* r, int64_t id) {
    auto it = r->labels.find(id);
    if (it == r->labels.end()) return;
    destroyLabel(r, it->second);
    r->labels.erase(it);
}

int sr_room_set_block(sr_room* r, int64_t id, const float centre[3], float yaw,
                      float roll, float size, uint32_t gl_texture, int tex_w, int tex_h) {
    if (!ensureBlockGeometry(r)) return -1;
    Engine& e = *r->engine;
    auto& tcm = e.getTransformManager();
    Block& b = r->blocks[id];
    if (b.entity.isNull()) {
        b.entity = utils::EntityManager::get().create();
        b.mi = r->blockMat->createInstance();
        RenderableManager::Builder(1)
                .boundingBox({ { -0.5f, -0.5f, -0.5f }, { 0.5f, 0.5f, 0.5f } })
                .material(0, b.mi)
                .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, r->cubeVb, r->cubeIb, 0, 36)
                .culling(true).castShadows(true).receiveShadows(true)
                .build(e, b.entity);
        tcm.create(b.entity);
        r->scene->addEntity(b.entity);
    }
    if (gl_texture != b.glName || tex_w != b.texW || tex_h != b.texH) {
        if (b.texture) e.destroy(b.texture);
        b.texture = Texture::Builder()
                .width(uint32_t(std::max(tex_w, 1))).height(uint32_t(std::max(tex_h, 1)))
                .levels(1).sampler(Texture::Sampler::SAMPLER_2D)
                .format(Texture::InternalFormat::RGBA8)
                .usage(Texture::Usage::SAMPLEABLE)
                .import(intptr_t(gl_texture))
                .build(e);
        b.glName = gl_texture; b.texW = tex_w; b.texH = tex_h;
        TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR);
        sampler.setWrapModeS(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        sampler.setWrapModeT(TextureSampler::WrapMode::CLAMP_TO_EDGE);
        b.mi->setParameter("image", b.texture, sampler);
    }
    tcm.setTransform(tcm.getInstance(b.entity),
            mat4f::translation(float3{ centre[0], centre[1], centre[2] })
            * mat4f::rotation(yaw, float3{ 0, 1, 0 })
            * mat4f::rotation(roll, float3{ 0, 0, 1 })
            * mat4f::scaling(float3{ size, size, size }));
    return 0;
}

void sr_room_remove_block(sr_room* r, int64_t id) {
    auto it = r->blocks.find(id);
    if (it == r->blocks.end()) return;
    destroyBlock(r, it->second);
    r->blocks.erase(it);
}

void sr_room_set_screen_intensity(sr_room* r, float intensity) {
    r->screenIntensity = intensity;
    for (auto& kv : r->panes) kv.second.screenMi->setParameter("intensity", intensity);
}

void sr_room_destroy(sr_room* r) {
    if (!r) return;
    if (r->engine) {
        r->engine->flushAndWait();
        for (auto& kv : r->panes) destroyPane(r, kv.second);
        r->panes.clear();
        for (auto& kv : r->orbs) destroyOrb(r, kv.second);
        r->orbs.clear();
        for (auto& kv : r->labels) destroyLabel(r, kv.second);
        r->labels.clear();
        for (auto& kv : r->blocks) destroyBlock(r, kv.second);
        r->blocks.clear();
        if (r->cubeVb) r->engine->destroy(r->cubeVb);
        if (r->cubeIb) r->engine->destroy(r->cubeIb);
        if (r->blockMat) r->engine->destroy(r->blockMat);
        if (r->havePointLight) {
            r->scene->remove(r->pointLight);
            r->engine->getLightManager().destroy(r->pointLight);
        }
        if (r->sphereVb) r->engine->destroy(r->sphereVb);
        if (r->sphereIb) r->engine->destroy(r->sphereIb);
        if (r->glowMat) r->engine->destroy(r->glowMat);
        if (r->labelMat) r->engine->destroy(r->labelMat);
        if (r->quadVb) r->engine->destroy(r->quadVb);
        if (r->quadIb) r->engine->destroy(r->quadIb);
        if (r->boxVb) r->engine->destroy(r->boxVb);
        if (r->boxIb) r->engine->destroy(r->boxIb);
        if (r->screenMat) r->engine->destroy(r->screenMat);
        if (r->frameMat) r->engine->destroy(r->frameMat);
        if (r->frameTexture) r->engine->destroy(r->frameTexture);
        if (r->frameBlank) r->engine->destroy(r->frameBlank);
        if (r->asset) {
            r->scene->removeEntities(r->asset->getRenderableEntities(),
                                     r->asset->getRenderableEntityCount());
            r->loader->destroyAsset(r->asset);
        }
        delete r->resources;
        delete r->stb;
        if (r->materials) { r->materials->destroyMaterials(); delete r->materials; }
        if (r->loader) gltfio::AssetLoader::destroy(&r->loader);
        if (r->haveSun) { r->scene->remove(r->sun); r->engine->getLightManager().destroy(r->sun); }
        if (r->target) r->engine->destroy(r->target);
        if (r->output) r->engine->destroy(r->output);
        if (r->skybox) r->engine->destroy(r->skybox);
        if (r->ibl) r->engine->destroy(r->ibl);
        if (r->iblTexture) r->engine->destroy(r->iblTexture);
        if (r->skyTexture) r->engine->destroy(r->skyTexture);
        r->engine->destroyCameraComponent(r->cameraEntity);
        r->engine->destroy(r->view);
        r->engine->destroy(r->scene);
        r->engine->destroy(r->renderer);
        r->engine->destroy(r->swapChain);
        Engine::destroy(&r->engine);
    }
    delete r->iblBundle;
    delete r->skyBundle;
    delete r->platform;
    delete r;
}

} // extern "C"
