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
