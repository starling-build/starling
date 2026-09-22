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
over RDP) from the female base model. Hair: the twin-tail hairstyle set with
a straight fringe, no ahoge, the four tail groups widened, thickened, twisted
and raised in the hairstyle editor, colour `#E2CA63`. Face: the sharper-eyed
face set with the eyes enlarged, irises `#1E66CA`, rose lipstick, near-black
eyeliner. Body: chest size and prominence raised, waist narrowed, legs a
little longer, and the eyes opened up (less inner slant, lower lower lid).
Outfit: the corset-and-blouse top recoloured black through the
texture editor's shader colours, then its collar, shoulders and lower
sleeves ERASED in the texture editor (both coat layers) so it reads as an
off-shoulder top with short puff sleeves; gothic frill skirt shortened and
flared; black choker; short black gloves; garter thigh-highs with the
right leg's black erased under an imported fishnet layer (`fishnet-leg.png`,
a diamond net masked to that leg's UV strip); black lace-up boots with the
sole raised. Source and export: `goth-agent.vroid` (reopen in VRoid Studio
to change anything) and `goth-agent.vrm` (VRM 1.0, 37k polygons,
`aa/ih/ou/ee/oh` + blinks + expressions). The lip-sync script takes it
unchanged:

```sh
/snap/bin/blender --factory-startup -b --python build/tools/blender-agent-avatar.py -- \
    --vrm design/blender/agent/goth-agent.vrm --audio line.wav --visemes line-visemes.json \
    --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out OUT --frames
```

VRoid Studio 2.x exports its shape keys as bare `Fcl_MTH_A` (older VRoid
exports and the pixiv samples carry a `Face_Blendshape.` prefix); the
script's key lookup accepts both.

### Blender refine pass

What VRoid Studio cannot do is done by `build/tools/blender-agent-refine.py`,
which runs on the scene the avatar script saves and edits it toward the
reference picture:

- **Top**: the blouse is cut into an off-shoulder top with short sleeves,
  puffed about the sleeve's own centre line, with a frill extruded from the
  cut edges. VRoid removes the body under clothing at export, so the upper
  arm is rebuilt as a skin tube from over the shoulder to the forearm's open
  edge, weighted across the elbow. The blouse's back panel stays, because
  there is no skin under it either.
- **Bodice**: the corset above the underbust line becomes navy cloth (its
  texture flattened and recoloured), with a ruffle on its top edge, so the
  black corset reads as an underbust piece over a navy dress.
- **Skirt**: the bell skirt becomes three tiers with handkerchief points and
  light piping on each hem; the white petticoat is dropped.
- **Hair**: the twin tails are re-pivoted at their real gather point on the
  head top (measured, 1.60 m), shortened, pulled in, waved and flared, and
  each strand gets two copies fanned in the frontal plane for volume. Black
  hair ties sit at the gather point. The hair texture is shifted to honey
  blonde and the irises to blue-violet.
- **Accessories**: satin choker with a see-through lace frill and a lace bib,
  a belt with a gold buckle, stocking bands with bows, forearm lacing.
- **Legs and skin**: the opaque stocking becomes a sheer brown-black
  (recoloured in the skin texture, only inside that leg's faces), the
  thighs are a little fuller, skin is warmer, and the arms hang slightly
  away from the body. The body skin loses its outline shell: VRoid's culled
  gaps under the old collar showed it as dark red, and the reference draws
  no skin contour lines.

Every new piece is weighted to a bone and every edited vertex keeps its
weights, so the rig, mouth shapes and the lip-sync script all keep working.
`build/tools/blender-agent-stage.py` renders the full-length character sheet
the reference uses: dark indigo stage, overhead spot, violet and pink rims,
neutral face.

```sh
blender -b --python build/tools/blender-agent-avatar.py -- --vrm goth-agent.vrm \
    --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out A --stills 1 ...
blender -b --python build/tools/blender-agent-refine.py -- --blend A/agent.blend --out R/agent.blend
blender -b --python build/tools/blender-agent-stage.py  -- R/agent.blend sheet.png
blender -b --python build/tools/blender-agent-avatar.py -- --blend R/agent.blend --audio line.wav \
    --visemes line-visemes.json --out CLIP --frames
```

`vroid-full.png` is the character sheet and `vroid-compare.png` puts it
beside the reference (`vroid-bust.png` / `vroid-speaking.png` are from the
earlier, unrefined clip). What still differs: the face is VRoid's (a longer chin, smaller
eyes than the reference), the skirt tiers are cut from one bell rather than
sewn as separate ruffles, and the lace is a procedural mesh rather than a
lace pattern.
