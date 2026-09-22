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
eyeliner. Body: head size at the minimum (the reference is about 7.7
heads tall), head width 0.15, neck length -0.45 and thickness 0.35,
chest size 0.52, waist narrowed, legs 0.55, small flat ears (size -0.8,
prominence -0.5) so the hair hides them, and a soft cheek blush. Face: the
masculine face setting removed and the feminine face, eyes and brows
raised, chin shortened, eyes at full size with larger irises, no scornful
look, a heavy winged eyeliner and bold lashes, and a full blunt fringe.
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

- **Top**: VRoid's sleeve is removed (its front was erased in VRoid) and a
  gathered puff sleeve is built on each upper arm from the shoulder joint
  to just above the elbow, fullest two-thirds of the way down, with frills on the off-shoulder line and the cuff,
  in the bodice's navy. `--vroid-sleeves` keeps and puffs VRoid's instead. VRoid removes the body under clothing at export, so the upper
  arm is rebuilt as a skin tube from over the shoulder to the forearm's open
  edge, weighted across the elbow. The blouse's back panel stays, because
  there is no skin under it either.
- **Blouse**: the corset above the underbust line becomes navy, and a
  fitted gathered blouse is built over the upper torso: its shape is the
  largest radius of the torso at each height and angle (so it bridges the
  bust like cloth), from under the corset's top edge to a straight
  off-shoulder neckline with a ruffle. What is left of VRoid's blouse, its
  upper-back panel, is recoloured to the same navy. The black corset then
  reads as an underbust piece over the blouse, with silver eyelets in two
  columns and criss-cross lacing.
- **Skirt**: the bell skirt is subdivided and becomes two layers of 16
  rounded pleats flaring from the belt (a knife-pleat sawtooth shows as
  teeth on the silhouette; layers in step so the outer nests), with six handkerchief points, a gathered
  frill under each hem and three rows of navy piping; its buttons and panel seams are flattened out of the
  texture and the white petticoat is dropped.
- **Corset and belt**: silver grommets and a criss-cross lacing down the
  front; the belt follows the corset's real cross-section with a small
  gold buckle.
- **Shading**: cloth cel shading is softened (VRoid ships it nearly hard)
  so pleats and gathers read, and the hair gets a warm ochre shade. The
  MToon rim light, which the VRM carries, is set warm gold on the hair and
  violet on the cloth for the reference's backlit glow. Skin is warmed in
  its texture, light texels only: VRoid paints the gloves dark grey into
  the same texture, and a warm tint or a skin rim turns them brown.
- **Hair texture**: VRoid's hair texture is a flat gradient, so it is
  repainted at twice the resolution with strand detail. The texture runs
  along each strand (root at the top of the image) and repeats across it,
  so everything is periodic across: seven clumps per repeat with darker
  gaps, 130 fine dark lines that run from the root and fade out, lighter
  streaks, a darker root and a broken sheen band. It replaces both the lit
  and the shade texture; the shade colour is a warm ochre.
- **Twin tails**: VRoid's curled strand ends are cut off first (past its
  lowest point along the mesh a curled strand turns back up, and a
  height-based reshape then scatters it into shards), along with its
  little root-cap cards at each gather point and loose cards the old long
  tails hid. Each strand is then laid along a path from its gather point:
  an arc that leaves the tie 60 degrees up and turns over to hang, a fall
  of 28 cm to the tops of the shoulders, and a 45-degree outward flick of
  the tips, with the cross-section carried across the arc and tapering to
  a point. Two copies of every strand with other spreads and lengths fill
  the bundle out. The ties wrap around the tails at the angle they leave
  the head. Measured against the reference at full length: the tails
  span about 2.6 face-widths and end at the shoulders.
- **Fringe and locks**: the fringe is lengthened from its hairline; the
  side pieces in front of the ears become fuller face-framing locks that
  run 4.5 cm past the chin, bowing out past the cheek and in toward the
  chin with pointed ends. The crown is scaled up a little. The hair is
  shifted to honey blonde and the irises to blue-violet.
- **Accessories**: satin choker with a see-through lace frill and a lace bib,
  a belt with a gold buckle, stocking bands with bows, and thin forearm
  lacing that zigzags across the front of each forearm in X's, each point
  ray-cast onto the skin (the forearm is not round, so a fixed radius floats).
- **Legs and skin**: the opaque stocking becomes a sheer brown-black
  (recoloured in the skin texture, only inside that leg's faces) with its
  own material whose brightness follows the view angle, so skin shows
  through where the leg faces you; the fishnet is redrawn at half the
  VRoid cell size; both stocking bands get a scalloped lace top; the
  thighs are a little fuller, skin is warmer, and the arms hang slightly
  away from the body. The body skin loses its outline shell: VRoid's culled
  gaps under the old collar showed it as dark red, and the reference draws
  no skin contour lines.

Heights that are not measured from the mesh are shifted by the hip bone's
offset from the model they were tuned on, so a VRoid change to leg or
torso length does not need new numbers. Every new piece is weighted to a bone and every edited vertex keeps its
weights, so the rig, mouth shapes and the lip-sync script all keep working.
`build/tools/blender-agent-stage.py` renders the full-length character sheet
the reference uses: dark indigo stage, overhead spot, violet and pink rims,
neutral face, and a relaxed stance (arms angled out past the flared skirt
with soft elbows and relaxed, curled fingers, one knee eased forward, a
slight turn through the hips and head). The pose is applied to the render only; `STAGE_POSE=saved`
keeps the scene's own pose. Its bone helper rotates about world axes
through each bone's head, parents first: a child bone's local rotation
is in its already-rotated parent's frame, so a "bend the elbow" about the
rest X axis became a twist along the forearm.

```sh
blender -b --python build/tools/blender-agent-avatar.py -- --vrm goth-agent.vrm \
    --addon-zip VRM_Addon_for_Blender-4_7_1.zip --out A --stills 1 ...
blender -b --python build/tools/blender-agent-refine.py -- --blend A/agent.blend --out R/agent.blend
blender -b --python build/tools/blender-agent-stage.py  -- R/agent.blend sheet.png
blender -b --python build/tools/blender-agent-avatar.py -- --blend R/agent.blend --audio line.wav \
    --visemes line-visemes.json --out CLIP --frames
```

`vroid-full.png` is the character sheet, `vroid-compare.png` puts it
beside the reference and `vroid-face-compare.png` does the same for the head (`vroid-bust.png` / `vroid-speaking.png` are from the
earlier, unrefined clip). `vroid-hair-angles.png` shows the hair from the side, back and above.
What still differs: the reference is rendered with a soft glow and
film-like lighting, and its lace has floral motifs.
