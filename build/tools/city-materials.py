"""PBR surfaces for the waterfront, with world-space UVs measured in metres.

The legacy atlas remains for actors, signage and emissive windows. Architecture
uses dedicated repeating images, so long walls never stretch a sixteen-pixel
tile across a whole building. Shared vertex buffers preserve face topology.
"""
from pathlib import Path

import numpy as np


def apply(doc, view, accessor, positions, normals, atlas_uv, indices, tiles, atlas_size, *, surface_overrides=None, normal_maps=None, material_extras=None):
    source = Path(__file__).resolve().parents[2] / "shell/Resources/Worlds/city/materials"
    # Color factors are linear (glTF), not sRGB swatches.
    plaster = {
        "plaster_cream": (.85, .74, .54),
        "plaster_terra": (.62, .29, .19),
        "plaster_sage": (.42, .56, .43),
        "plaster_blue": (.36, .50, .65),
        "plaster_rose": (.68, .40, .39),
    }
    surfaces = {name: ("lime-plaster.png", color, .88, 0., 2.)
                for name, color in plaster.items()}
    surfaces.update({
        "limestone": ("limestone.png", (.95, .78, .53), .78, 0., 2.),
        "stone": ("limestone.png", (.50, .42, .31), .9, 0., 2.),
        "sidewalk": ("limestone.png", (.70, .59, .44), .9, 0., 2.),
        "plaza": ("limestone.png", (.64, .53, .40), .86, 0., 2.),
        "paving_border": (None, (.19, .23, .23), .9, 0., 1.),
        "copper": (None, (.16, .25, .16), .48, .55, 1.),
        "bronze": (None, (.25, .15, .065), .38, .7, 1.),
        "glass": (None, (.055, .11, .17), .19, .25, 1.),
        "leaves": (None, (.13, .17, .055), .95, 0., 1.),
        "leaves_light": (None, (.23, .28, .085), .95, 0., 1.),
        "leaves_dark": (None, (.065, .095, .035), .95, 0., 1.),
        "log": (None, (.12, .075, .035), .95, 0., 1.),
        "interior_warm": (None, (.50, .31, .15), .6, 0., 1.),
        "curtain": (None, (.60, .51, .36), .95, 0., 1.),
        "painted_wood": (None, (.035, .085, .065), .55, 0., 1.),
        "flower_rose": (None, (.52, .08, .11), .8, 0., 1.),
        "flower_ochre": (None, (.85, .40, .045), .8, 0., 1.),
    })
    surfaces.update(surface_overrides or {})
    normal_maps = normal_maps or {}
    material_extras = material_extras or {}
    doc["samplers"].append({"magFilter": 9729, "minFilter": 9987,
                            "wrapS": 10497, "wrapT": 10497})
    sampler = len(doc["samplers"]) - 1
    textures = {}
    # Group triangles by their original atlas tile; never duplicate faces.
    tile_ids = (np.floor(atlas_uv[:, 1] * atlas_size).astype(int) * atlas_size
                + np.floor(atlas_uv[:, 0] * atlas_size).astype(int))
    triangles = indices.reshape(-1, 3)
    triangle_tiles = tile_ids[triangles[:, 0]]
    remaining = np.ones(len(triangles), dtype=bool)
    primitives = []
    uv_accessors = {}
    for name, (filename, color, roughness, metal, metres) in surfaces.items():
        selected = triangle_tiles == tiles[name]
        if not selected.any():
            continue
        remaining &= ~selected
        pbr = {"baseColorFactor": [*color, 1.], "roughnessFactor": roughness,
               "metallicFactor": metal}
        if filename:
            if filename not in textures:
                image = len(doc["images"])
                doc["images"].append({"bufferView": view((source / filename).read_bytes()),
                                      "mimeType": "image/png", "name": filename})
                textures[filename] = len(doc["textures"])
                doc["textures"].append({"sampler": sampler, "source": image})
            pbr["baseColorTexture"] = {"index": textures[filename]}
        material = len(doc["materials"])
        doc["materials"].append({"name": name, "pbrMetallicRoughness": pbr})
        if name == "interior_warm":
            doc["materials"][-1]["emissiveFactor"] = [.30,.15,.04]
        if name in normal_maps:
            path, strength = normal_maps[name]
            image = len(doc["images"])
            doc["images"].append({"bufferView": view(Path(path).read_bytes()),
                                  "mimeType": "image/png", "name": Path(path).name})
            texture = len(doc["textures"])
            doc["textures"].append({"sampler": sampler, "source": image})
            doc["materials"][-1]["normalTexture"] = {"index": texture, "scale": strength}
        doc["materials"][-1].update(material_extras.get(name, {}))
        # Dominant-axis projection uses global position. Adjacent terrain
        # strips share the same phase; detail size stays constant on any face.
        if metres not in uv_accessors:
            axis = np.argmax(np.abs(normals), axis=1)
            uv = np.empty((len(positions), 2), np.float32)
            for normal_axis, plane in ((0, (2, 1)), (1, (0, 2)), (2, (0, 1))):
                mask = axis == normal_axis
                uv[mask] = positions[mask][:, plane] / metres
            uv_accessors[metres] = accessor(uv, "VEC2", target=34962)
        primitives.append({"attributes": {"POSITION": 0, "NORMAL": 1,
                            "TEXCOORD_0": uv_accessors[metres]},
                           "indices": accessor(triangles[selected].reshape(-1),
                                               "SCALAR", 5125, 34963),
                           "material": material, "mode": 4})
    legacy = doc["meshes"][0]["primitives"][0]
    if remaining.any():
        legacy["indices"] = accessor(triangles[remaining].reshape(-1), "SCALAR", 5125, 34963)
        primitives.insert(0, legacy)
    doc["meshes"][0]["primitives"] = primitives
