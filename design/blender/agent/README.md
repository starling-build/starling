# Speaking agent avatar — Blender study

A stylised AI-agent character speaking a sample line with lip sync, rendered
by Blender. The pipeline is four free pieces, all driven from one script:

1. **Character**: the VRM consortium's sample model *Seed-san* (short dark
   hair, cyan tech trim, robot-arm pack), which ships rigged with mouth,
   blink, brow and expression shape keys. Download:
   `https://github.com/vrm-c/vrm-specification/raw/master/samples/Seed-san/vrm/Seed-san.vrm`
   (sample-model licence; swap in any VRM with A/I/U/E/O lip shapes).
2. **Voice**: `edge-tts` (voice `en-US-AvaNeural`) speaks `line.txt` to
   `line.mp3`; ffmpeg converts it to 16-bit mono WAV for the next step.
3. **Mouth timing**: Rhubarb Lip Sync reads the WAV and writes
   `line-visemes.json`, a timeline of nine mouth shapes (A–H, X).
4. **Blender**: `build/tools/blender-agent-avatar.py` imports the VRM through
   the VRM add-on (`VRM_Addon_for_Blender-4_7_1.zip` from
   saturday06/VRM-Addon-for-Blender), poses the arms down from the T-pose,
   sets a bust camera, a warm key, cool fill, a strong cyan rim and a soft
   halo ring on a dark gradient backdrop, keys the lip shapes from the
   Rhubarb cues with ~70 ms transitions, and layers blinks, brow lifts, eye
   drift and slow idle head, neck and chest motion on top. EEVEE renders
   the frames; ffmpeg muxes them with the voice.

Rebuild (paths as used on the dev box):

```sh
python3 -m venv ~/tmp/avatar/venv && ~/tmp/avatar/venv/bin/pip install edge-tts
~/tmp/avatar/venv/bin/edge-tts --voice en-US-AvaNeural --rate=-4% \
    --text "$(cat design/blender/agent/line.txt)" --write-media line.mp3
ffmpeg -y -i line.mp3 -ac 1 -ar 44100 -sample_fmt s16 line.wav
rhubarb -f json --extendedShapes GX -o line-visemes.json line.wav
/snap/bin/blender --factory-startup -b --python build/tools/blender-agent-avatar.py -- \
    --vrm Seed-san.vrm --audio line.wav --visemes line-visemes.json \
    --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out OUT --width 1280 --height 720 --frames
ffmpeg -y -framerate 30 -i OUT/frames/f%04d.png -i line.wav -c:v libx264 -pix_fmt yuv420p \
    -crf 18 -c:a aac -shortest agent-speaking.mp4
```

`--stills 12,40,150` renders single frames for checking pose and mouth
shapes without the full sequence. Rhubarb's shapes map to the VRM lips as:
A closed, B teeth apart (i), C open (e), D wide (a), E rounded (o), F
puckered (u), G f/v (i+u), H l (e+a), X rest.

Known limits: the mouth interior is the model's own (a flat tongue card), so
extreme close-ups show its anime origin; the character is stylised by
design, since a photoreal face in real time would look uncanny. The same
viseme stream can drive the model live in the desktop renderer later.

## Gothic twin-tail variant

`build/tools/blender-agent-goth.py` dresses the VRoid sample girl
(`VRM1_Constraint_Twist_Sample.vrm` from pixiv/three-vrm) as a blonde
twin-tail gothic character after a reference image: it hue-shifts the hair
textures to blonde and the iris to blue (and re-packs them, or a reopened
.blend shows the originals), cuts the hair to ear level with a bisect so
bangs and crown remain, builds six tapered curve strands per twin tail with
strand shading and hair ties, tints the shirt, shorts and shoes black
through their MToon colour factors, and adds toon-shaded meshes fitted to
the body's measured radii: an off-shoulder frill with lace edge, puff
sleeves, gloves, a corset with lacing and a belt with a gold buckle, a
two-layer pleated skirt with hem trim, a lace choker, one opaque and one
fishnet thigh-high (procedural diamond mesh with hashed alpha) with bows,
and platform lace-up boots. Every piece is parented to the matching bone
(the parent space sits at the bone *tail*, so the inverse matrix includes
the bone length), so she poses and animates with the rig.

```sh
/snap/bin/blender --factory-startup -b --python build/tools/blender-agent-goth.py -- \
    --vrm VRM1_Constraint_Twist_Sample.vrm --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out OUT
/snap/bin/blender --factory-startup -b --python build/tools/blender-agent-avatar.py -- \
    --blend OUT/goth.blend --audio line.wav --visemes line-visemes.json --out CLIP --frames
```

`--blend` makes the lip-sync script start from the prepared scene, keeping
its pose, lights and `Bust camera`, and only layering the mouth, blink and
head animation. `goth-full.png` and `goth-bust.png` are the character
stills; `goth-speaking.png` is a frame from her clip.

## VRoid Studio version (current)

The scripted goth rebuild above never got close to the reference picture:
hair and cloth built from primitives look like primitives. The character
is now made in **VRoid Studio 2.14** (free, Windows; on the build box, driven
over RDP) from the female base model: twin-tail hairstyle set with a
straight fringe, hair `#E2CA63`, irises `#1E66CA`, the corset-and-blouse
top recoloured black through the texture editor's shader colours with the
shoulders puffed, the gothic frill skirt shortened and flared, lace choker,
short black gloves, garter thigh-highs and buckle boots. Source and export:
`goth-agent.vroid` (reopen in VRoid Studio to change anything) and
`goth-agent.vrm` (VRM 1.0, 38k polygons, `aa/ih/ou/ee/oh` + blinks +
expressions). The lip-sync script takes it unchanged:

```sh
/snap/bin/blender --factory-startup -b --python build/tools/blender-agent-avatar.py -- \
    --vrm design/blender/agent/goth-agent.vrm --audio line.wav --visemes line-visemes.json \
    --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out OUT --frames
```

VRoid Studio 2.x exports its shape keys as bare `Fcl_MTH_A` (older VRoid
exports and the pixiv samples carry a `Face_Blendshape.` prefix); the
script's key lookup accepts both. `vroid-full.png` and `vroid-bust.png` are
the renders, `vroid-compare.png` puts the reference beside three frames.

Still open against the picture: the top has long sleeves and a high collar
where the reference is off-shoulder with short puffs, and one stocking
should be fishnet.
