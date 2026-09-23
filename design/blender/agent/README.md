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
eyeliner. Body: head size -0.4 and chin length 0.05, measured with
`build/tools/agent-proportions.py` so she is 7.2 heads tall with the
eye-to-chin distance of the reference (an earlier -1.0 head and -0.42 chin
made her 7.9 heads, a head visibly too small), head width 0.15, neck length 0.25 and thickness 0.35 (chin to neckline
5.85% of height, reference 5.9%; an earlier -0.45 made the neck 12% short),
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

- **Arms and sleeves**: VRoid builds no skin under a long sleeve, so each
  upper arm is rebuilt as a skin tube from inside the shoulder to the
  forearm, with a real arm profile (round shoulder cap, full upper arm
  tapering to the elbow) instead of a thin cylinder. Its bone weights, and
  the sleeve's, are copied from VRoid's own long-sleeved blouse before that
  is cut away, so they bend smoothly across the shoulder. The puff sleeve
  starts 6 cm down the arm on top and 2 cm underneath, so the round bare
  shoulder cap shows above it; it is full just below the neckline, hangs,
  and gathers into a cuff above the elbow, sized off the arm profile. It
  has a ruffle on its top edge and on the cuff, in the blouse navy.
  `--vroid-sleeves` keeps and puffs VRoid's sleeve instead.
- **Waist**: the reference's corset cinches to about half the shoulder
  width, and VRoid's torso was 30-40% wider there. Every vertex of the
  torso (skin, corset, the skirt's waistband) is narrowed by one smooth
  factor per height - 0.78 at the belt, 0.82 at the underbust, 0.88
  across the bust, back to 1 under the arms - so the layers stay nested
  and everything built afterwards follows. Only 40% of it applies front
  to back, which leaves the waist round rather than flat.
- **Blouse**: a fitted gathered blouse is built over the upper torso,
  shaped as a bust: tucked into the corset's top edge, a round underside,
  fullest a third of the way up with two soft forms on the front, then
  sloping back to a straight off-shoulder neckline with a ruffle. Its
  sides come from the ribs' real outline; guessing them from the front
  made the old blouse a box. Everything VRoid had under it goes: the
  loose long-sleeve blouse (it stood 2 cm off the ribs) and the corset's
  flat top panel, cut clean at the underbust line. The black corset then
  reads as an underbust piece over the blouse, with a narrow binding on
  its top edge.
- **Skirt**: VRoid's bell skirt is replaced by one built from scratch after
  the reference: 20 panels, each a soft roll with a valley at its fold,
  knife-pleated so it laps a little over the next (mirrored left and
  right, the centre front and back panels flat) and the hems step at
  each fold. Measured on the reference, its skirt spans about 2:1 from
  the light middle of a panel to its dark valleys; flat panels with thin
  fold lines gave 1.4:1 and read as a lampshade. It flares out fast below
  the belt as over a petticoat, in two tiers whose hems make a V from the
  front - short at the sides, a deep point at the centre front and back.
  The upper tier stands out to wide corners at the sides (40% down the
  figure, like the reference) while the lower tier hangs narrower and
  steeper under it; about 7 cm of it shows below the upper tier at the
  front, as in the reference (4 cm stacked the two hem bands into
  stripes). Each hem is a band standing off its tier, a shade darker,
  with two thin light cords along its edges and a rolled edge; there is
  no frill under it, as in the reference. Toon shading flattens the
  panels to one tone from the front, so the creases are also painted into
  a small texture of their own (a dark line at each fold, a soft falloff
  across each panel, and a shadow on the lower tier just under the upper
  one's edge). Bone
  weights are copied from VRoid's skirt by angle and relative depth
  (hips, spine and its skirt bones). With the shorter skirt, the garter
  straps VRoid paints up the thighs are painted out: the reference's
  thighs are bare between the stocking tops and the skirt.
- **Corset and belt**: VRoid's corset flares out at the bottom (over the
  skirt's waistband) and at the top (where its bust cups start); it is
  now a straight tube 8% wider at the top than at the belt, with the skin
  kept inside, and its texture is flattened so the side straps VRoid
  painted on it do not read as stripes. The flattened textures are also
  given to each cloth's MToon outline shell, which carries its own copy of
  the texture. Five pairs of silver eyelets 8 cm apart hold a dark lacing
  laid on the corset's curved surface (straight ribbons between eyelets
  cut through it and showed only as stubs). The lacing gap at the front,
  which VRoid leaves as bare skin, becomes plain corset. The belt follows the corset's outline 1 cm proud
  of it, as it sits on the skirt's gathered waistband, and the skirt's
  waistband tucks under the belt at the corset's width, so the skirt
  flares from the narrow waist.
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
- **Neck and shoulders**: VRoid's blouse left a stand-up collar behind the
  neck and built no skin under it. Above the neckline that collar becomes
  double-sided skin, clamped under a smooth trapezius curve that falls
  steeply from just below the choker and flattens out to the shoulder
  joint, so the neck runs down into sloping shoulders instead of ending at
  a navy collar. The skin texture's empty texels (left where clothing hid
  the body) are filled by growing the surrounding colour. The choker sits
  19% up the neck bone, 3 cm tall, with bare neck above it as in the
  reference.
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
neutral face, and a relaxed stance (upper arms hanging close to the body,
forearms angled out past the flared skirt, soft elbows and relaxed, curled fingers, one knee eased forward, a
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
