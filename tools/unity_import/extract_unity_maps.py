#!/usr/bin/env python3
"""One-off Unity -> Godot asset extractor for the HappyHarvest port.

Reads the Unity project (scenes, .png.meta sprite sheets, audio) and emits:
  out/<scene>.json   tilemap manifests: [{layer_name, sorting_order, cells:[...]}]
  out/<scene>_props.json   SpriteRenderer props (name, position, sprite, order)
  out/<scene>_prefabs.json prefab instances (name/guid/position) for manual pass
  out/crop_init.json crop initializer beds (cell, crop, stage)
  out/textures.json  texture inventory (unity path -> godot path, size)
plus copies referenced PNGs into art/ and all audio into audio/ (snake_case).

Coordinate conventions handled here so downstream stays dumb:
  - Unity cell (x, y) y-up  -> Godot cell (x, -y - 1) y-down.
  - Unity sprite rect origin bottom-left -> Godot region origin top-left:
        godot_y = tex_height - rect.y - rect.height
Cells' sprite regions are asserted 64-aligned after transform (tile sheets).
"""

import json
import os
import re
import shutil
import struct
import sys

import yaml

try:
    from yaml import CSafeLoader as SafeLoader
except ImportError:  # pragma: no cover
    from yaml import SafeLoader

UNITY_ROOT = "/Volumes/Speedy/Code/Rust/work/platform-sample-game-client-unity"
GODOT_ROOT = "/Volumes/Speedy/Code/Rust/work/platform-sample-game-client-godot"
OUT_DIR = os.path.join(GODOT_ROOT, "tools/unity_import/out")

SCENES = {
    "farm_outdoor": "Assets/HappyHarvest/Scenes/Farm_Outdoor.unity",
    "house_interior": "Assets/HappyHarvest/Scenes/House_Interior.unity",
}

CROP_INITIALIZER_GUID = "dde04bdb5ee6fdf4c97d49bb04a61cfe"
PPU = 64  # spritePixelsToUnits everywhere in this project

CLASS_GAMEOBJECT = 1
CLASS_TRANSFORM = 4
CLASS_SPRITERENDERER = 212
CLASS_MONOBEHAVIOUR = 114
CLASS_TILEMAP = 1839735485
CLASS_TILEMAP_RENDERER = 483693784
CLASS_TILEMAP_COLLIDER = 19719996
CLASS_PREFAB_INSTANCE = 1001

DOC_RE = re.compile(r"^--- !u!(\d+) &(\d+)( stripped)?\s*$", re.M)

SINGLE_SPRITE_FILEID = 21300000


def png_size(path):
    with open(path, "rb") as f:
        header = f.read(33)
    assert header[:8] == b"\x89PNG\r\n\x1a\n", f"not a png: {path}"
    w, h = struct.unpack(">II", header[16:24])
    return w, h


def snake(name):
    name = name.replace(" ", "_")
    name = re.sub(r"[^A-Za-z0-9_./-]", "_", name)
    return name.lower()


# ---------------------------------------------------------------- meta files

def load_sprite_meta(meta_path):
    """Parse a .png.meta -> {ppu, sprites: {fileID: {name, rect}}, single}."""
    with open(meta_path) as f:
        data = yaml.load(f, Loader=SafeLoader)
    ti = data.get("TextureImporter")
    if ti is None:
        return None
    ppu = ti.get("spritePixelsToUnits", 100)
    sprites = {}
    sheet = ti.get("spriteSheet") or {}
    for s in sheet.get("sprites") or []:
        rect = s["rect"]
        # physicsShape paths: points relative to sprite center, y-up ->
        # godot tile-polygon space (center origin, y-down): (x, -y)
        physics = [[[p["x"], -p["y"]] for p in path]
                   for path in (s.get("physicsShape") or [])]
        sprites[int(s["internalID"])] = {
            "name": s["name"],
            "rect": [rect["x"], rect["y"], rect["width"], rect["height"]],
            "pivot": [s.get("pivot", {}).get("x", 0.5), s.get("pivot", {}).get("y", 0.5)],
            "physics": physics,
        }
    # Also honor the name table in case internalID is missing for some entries.
    table = (ti.get("spriteSheet") or {}).get("nameFileIdTable") or {}
    by_name = {v["name"]: v for v in sprites.values()}
    for name, file_id in table.items():
        if int(file_id) not in sprites and name in by_name:
            sprites[int(file_id)] = by_name[name]
    return {
        "ppu": ppu,
        "sprites": sprites,
        "single": ti.get("spriteMode") == 1,
    }


def index_textures():
    """guid -> {png (abs), meta, rel (unity rel path), size, sprites...}"""
    index = {}
    art_roots = [
        "Assets/HappyHarvest",
        "Assets/Enjin Integration",
        "Assets/Free Game Items",
        "Assets/Gems and gold",
    ]
    for root in art_roots:
        abs_root = os.path.join(UNITY_ROOT, root)
        if not os.path.isdir(abs_root):
            continue
        for dirpath, _dirnames, filenames in os.walk(abs_root):
            for fn in filenames:
                if not fn.endswith(".png.meta"):
                    continue
                meta_path = os.path.join(dirpath, fn)
                png_path = meta_path[: -len(".meta")]
                if not os.path.exists(png_path):
                    continue
                with open(meta_path) as f:
                    head = f.read(200)
                m = re.search(r"guid: ([0-9a-f]{32})", head)
                if not m:
                    continue
                guid = m.group(1)
                index[guid] = {
                    "png": png_path,
                    "meta": meta_path,
                    "rel": os.path.relpath(png_path, UNITY_ROOT),
                    "parsed": None,  # lazy
                    "size": None,
                }
    return index


def texture_entry(tex_index, guid):
    entry = tex_index.get(guid)
    if entry is None:
        return None
    if entry["parsed"] is None:
        entry["parsed"] = load_sprite_meta(entry["meta"]) or {"ppu": PPU, "sprites": {}, "single": True}
        entry["size"] = png_size(entry["png"])
    return entry


def resolve_sprite(tex_index, guid, file_id):
    """-> (entry, godot_rect [x,y,w,h] top-left origin, pivot, physics) or None."""
    entry = texture_entry(tex_index, guid)
    if entry is None:
        return None
    tex_w, tex_h = entry["size"]
    spr = entry["parsed"]["sprites"].get(int(file_id))
    if spr is None:
        # single-sprite textures (and 21300000 refs into them) = full rect
        if file_id == SINGLE_SPRITE_FILEID or entry["parsed"]["single"]:
            return entry, [0, 0, tex_w, tex_h], [0.5, 0.5], []
        return None
    x, y, w, h = spr["rect"]
    return (entry, [int(x), int(tex_h - y - h), int(w), int(h)], spr["pivot"],
            spr.get("physics") or [])


# ---------------------------------------------------------------- scene file

def parse_scene(path):
    """-> {anchor: (class_id, doc_dict)}"""
    with open(path) as f:
        text = f.read()
    docs = {}
    matches = list(DOC_RE.finditer(text))
    for i, m in enumerate(matches):
        class_id = int(m.group(1))
        anchor = int(m.group(2))
        start = m.end() + 1
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        body = text[start:end]
        try:
            doc = yaml.load(body, Loader=SafeLoader)
        except yaml.YAMLError as e:
            print(f"  WARN: yaml parse failed for !u!{class_id} &{anchor}: {e}", file=sys.stderr)
            continue
        if doc:
            docs[anchor] = (class_id, doc[next(iter(doc))], next(iter(doc)))
    return docs


IDENTITY = {"e00": 1, "e01": 0, "e02": 0, "e03": 0,
            "e10": 0, "e11": 1, "e12": 0, "e13": 0,
            "e20": 0, "e21": 0, "e22": 1, "e23": 0,
            "e30": 0, "e31": 0, "e32": 0, "e33": 1}


def is_identity(matrix):
    return all(abs(matrix.get(k, 0) - v) < 1e-6 for k, v in IDENTITY.items())


def build_maps(docs):
    """Helper lookup tables over a parsed scene."""
    go_name = {}        # gameobject anchor -> name
    go_components = {}  # gameobject anchor -> [(class_id, comp_anchor)]
    transforms = {}     # transform anchor -> doc
    transform_of_go = {}
    for anchor, (class_id, doc, _tag) in docs.items():
        if class_id == CLASS_GAMEOBJECT:
            go_name[anchor] = doc.get("m_Name", "?")
        elif class_id == CLASS_TRANSFORM:
            transforms[anchor] = doc
            go = doc.get("m_GameObject", {}).get("fileID", 0)
            transform_of_go[go] = anchor
    for anchor, (class_id, doc, _tag) in docs.items():
        go_ref = doc.get("m_GameObject") if isinstance(doc, dict) else None
        if isinstance(go_ref, dict):
            go = go_ref.get("fileID", 0)
            go_components.setdefault(go, []).append((class_id, anchor))
    return go_name, go_components, transforms, transform_of_go


def world_position_from_transform(transforms, t_anchor):
    """Walk the parent chain summing local positions (no rotation in use)."""
    x = y = 0.0
    sx = sy = 1.0
    guard = 0
    while t_anchor and guard < 64:
        t = transforms.get(t_anchor)
        if t is None:
            break
        lp = t.get("m_LocalPosition", {})
        ls = t.get("m_LocalScale", {"x": 1, "y": 1})
        x = x * ls.get("x", 1) + lp.get("x", 0)
        y = y * ls.get("y", 1) + lp.get("y", 0)
        sx *= ls.get("x", 1)
        sy *= ls.get("y", 1)
        t_anchor = t.get("m_Father", {}).get("fileID", 0) or None
        guard += 1
    return x, y, sx, sy


def world_position(transforms, transform_of_go, docs, go_anchor):
    return world_position_from_transform(transforms, transform_of_go.get(go_anchor))


def extract_tilemaps(docs, tex_index, scene_name, prefab_index=None,
                     tile_objects_out=None, tile_physics=None):
    go_name, go_components, transforms, transform_of_go = build_maps(docs)
    layers = []
    if tile_physics is None:
        tile_physics = {}
    warned_matrices = 0
    animated = 0
    for anchor, (class_id, doc, _tag) in sorted(docs.items()):
        if class_id != CLASS_TILEMAP:
            continue
        tiles = doc.get("m_Tiles") or []
        if not tiles:
            continue
        go = doc.get("m_GameObject", {}).get("fileID", 0)
        name = go_name.get(go, f"tilemap_{anchor}")
        sorting_order = 0
        has_collider = False
        for cid, comp_anchor in go_components.get(go, []):
            if cid == CLASS_TILEMAP_RENDERER:
                sorting_order = docs[comp_anchor][1].get("m_SortingOrder", 0)
            elif cid == CLASS_TILEMAP_COLLIDER:
                has_collider = True
        sprite_array = doc.get("m_TileSpriteArray") or []
        matrix_array = doc.get("m_TileMatrixArray") or []
        object_array = doc.get("m_TileObjectToInstantiateArray") or []
        if doc.get("m_AnimatedTiles"):
            animated += len(doc["m_AnimatedTiles"])
        # Tilemap GO may itself be offset from the grid. 1 unit == 1 cell, so a
        # whole-unit offset shifts cell coordinates; fractional remainders are
        # dropped with a warning (only Water has a 0.009 jitter in practice).
        ox, oy, _sx, _sy = world_position(transforms, transform_of_go, docs, go)
        cell_dx, cell_dy = round(ox), round(oy)
        if abs(ox - cell_dx) > 0.05 or abs(oy - cell_dy) > 0.05:
            print(f"  WARN: tilemap '{name}' fractional offset ({ox}, {oy}) dropped")
        if cell_dx or cell_dy:
            print(f"  NOTE: tilemap '{name}' shifted by cells ({cell_dx}, {cell_dy})")
        anchor_off = doc.get("m_TileAnchor", {"x": 0.5, "y": 0.5})
        cells = []
        for t in tiles:
            pos = t["first"]
            td = t["second"]
            mi = td.get("m_TileMatrixIndex", 0)
            if matrix_array and mi < len(matrix_array):
                if not is_identity(matrix_array[mi].get("m_Data", IDENTITY)):
                    warned_matrices += 1
            ux0 = pos["x"] + cell_dx
            uy0 = pos["y"] + cell_dy
            # Tiles that instantiate prefabs instead of drawing sprites
            # (ObjectsInTiles layer: fences etc.) -> record for the prop pass.
            oi = td.get("m_TileObjectToInstantiateIndex", 65535)
            if oi != 65535 and oi < len(object_array) and tile_objects_out is not None:
                oref = object_array[oi].get("m_Data") or {}
                if oref.get("guid"):
                    tile_objects_out.append({
                        "cell": [ux0, -uy0 - 1],
                        "prefab_guid": oref["guid"],
                        "layer_name": name,
                    })
            si = td.get("m_TileSpriteIndex", 65535)
            if si >= len(sprite_array):
                continue
            ref = sprite_array[si].get("m_Data") or {}
            guid = ref.get("guid")
            file_id = ref.get("fileID", 0)
            if not guid or not file_id:
                continue
            resolved = resolve_sprite(tex_index, guid, file_id)
            if resolved is None:
                print(f"  WARN: unresolved sprite {file_id} guid {guid} in '{name}'")
                continue
            entry, rect, _pivot, physics = resolved
            if has_collider and physics:
                key = f"{entry['rel']}|{rect[0]}|{rect[1]}|{rect[2]}|{rect[3]}"
                tile_physics[key] = physics
            cells.append({
                "x": ux0,
                "y": -uy0 - 1,  # unity y-up -> godot y-down
                "texture": entry["rel"],
                "rect": rect,
            })
        layers.append({
            "layer_name": name,
            "sorting_order": sorting_order,
            "has_collider": has_collider,
            "tile_anchor": [anchor_off.get("x", 0.5), anchor_off.get("y", 0.5)],
            "cells": cells,
        })
    layers.sort(key=lambda l: l["sorting_order"])
    if warned_matrices:
        print(f"  WARN: {warned_matrices} cells use non-identity tile matrices (flips/rotations dropped)")
    if animated:
        print(f"  NOTE: {animated} animated tiles present (baked static; re-add water anim later)")
    print(f"  {scene_name}: {len(layers)} populated tilemap layers, "
          f"{sum(len(l['cells']) for l in layers)} cells")
    return layers


def extract_props(docs, tex_index):
    go_name, go_components, transforms, transform_of_go = build_maps(docs)
    props = []
    for anchor, (class_id, doc, _tag) in sorted(docs.items()):
        if class_id != CLASS_SPRITERENDERER:
            continue
        go = doc.get("m_GameObject", {}).get("fileID", 0)
        # skip renderers living on tilemap GameObjects (none expected, but safe)
        if any(cid == CLASS_TILEMAP for cid, _a in go_components.get(go, [])):
            continue
        ref = doc.get("m_Sprite") or {}
        guid = ref.get("guid")
        file_id = ref.get("fileID", 0)
        if not guid:
            continue
        name = go_name.get(go, f"prop_{anchor}")
        if "_mask" in name.lower():
            continue  # SpriteMask light-cutout children, not visuals
        resolved = resolve_sprite(tex_index, guid, file_id)
        if resolved is None:
            continue
        entry, rect, pivot, _physics = resolved
        # Unity world size = pixels / texture PPU; our px space is 64/unit.
        ppu_scale = PPU / float(entry["parsed"]["ppu"] or PPU)
        x, y, sx, sy = world_position(transforms, transform_of_go, docs, go)
        props.append({
            "name": name,
            # unity units (y-up) -> godot px (y-down)
            "position": [round(x * PPU, 2), round(-y * PPU, 2)],
            "scale": [round(sx * ppu_scale, 4), round(sy * ppu_scale, 4)],
            "texture": entry["rel"],
            "rect": rect,
            "pivot": pivot,  # unity pivot (0..1, y-up, relative to rect)
            "sorting_order": doc.get("m_SortingOrder", 0),
            "sorting_layer_id": doc.get("m_SortingLayerID", 0),
            "flip_x": bool(doc.get("m_FlipX", 0)),
            "flip_y": bool(doc.get("m_FlipY", 0)),
        })
    print(f"  {len(props)} sprite props")
    return props


def index_prefabs():
    """guid -> abs path of .prefab, for all sample-asset roots."""
    index = {}
    for root in ["Assets/HappyHarvest", "Assets/Enjin Integration",
                 "Assets/Free Game Items", "Assets/Gems and gold"]:
        abs_root = os.path.join(UNITY_ROOT, root)
        if not os.path.isdir(abs_root):
            continue
        for dirpath, _dirnames, filenames in os.walk(abs_root):
            for fn in filenames:
                if not fn.endswith(".prefab.meta"):
                    continue
                meta_path = os.path.join(dirpath, fn)
                with open(meta_path) as f:
                    m = re.search(r"guid: ([0-9a-f]{32})", f.read(200))
                if m:
                    index[m.group(1)] = meta_path[: -len(".meta")]
    return index


_PREFAB_SPRITE_CACHE = {}


def prefab_root_sprite(prefab_index, guid):
    """Resolve a prefab's visual: its root-most SpriteRenderer sprite ref,
    that renderer's sorting order, and whether the prefab is animated/scripted
    (Animator or MonoBehaviour present -> gameplay object, not a static prop).
    Returns dict or None."""
    if guid in _PREFAB_SPRITE_CACHE:
        return _PREFAB_SPRITE_CACHE[guid]
    path = prefab_index.get(guid)
    result = None
    if path and os.path.exists(path):
        docs = parse_scene(path)
        has_animator = any(cid == 95 for cid, _d, _t in docs.values())
        has_script = any(cid == CLASS_MONOBEHAVIOUR for cid, _d, _t in docs.values())
        renderers = []
        names, _comps, transforms, transform_of_go = build_maps(docs)
        for anchor, (class_id, doc, _tag) in sorted(docs.items()):
            if class_id != CLASS_SPRITERENDERER:
                continue
            ref = doc.get("m_Sprite") or {}
            if not ref.get("guid"):
                continue
            go = doc.get("m_GameObject", {}).get("fileID", 0)
            if "_mask" in names.get(go, "").lower():
                continue  # SpriteMask light-cutout children, not visuals
            # Walk up to but EXCLUDING the prefab root: the root transform in a
            # .prefab file stores a stale position that the scene instance
            # overrides via m_Modification (we add the instance position later).
            x = y = 0.0
            sx = sy = 1.0
            t_anchor = transform_of_go.get(go)
            guard = 0
            while t_anchor and guard < 64:
                t = transforms.get(t_anchor)
                if t is None:
                    break
                father = t.get("m_Father", {}).get("fileID", 0)
                if not father:
                    break  # prefab root: skip its local position
                lp = t.get("m_LocalPosition", {})
                ls = t.get("m_LocalScale", {"x": 1, "y": 1})
                x = x * ls.get("x", 1) + lp.get("x", 0)
                y = y * ls.get("y", 1) + lp.get("y", 0)
                sx *= ls.get("x", 1)
                sy *= ls.get("y", 1)
                t_anchor = father
                guard += 1
            renderers.append({
                "sprite_guid": ref["guid"],
                "sprite_file_id": ref.get("fileID", 0),
                "local_offset": [round(x * PPU, 2), round(-y * PPU, 2)],
                "local_scale": [sx, sy],
                "sorting_order": doc.get("m_SortingOrder", 0),
                "flip_x": bool(doc.get("m_FlipX", 0)),
            })
        if renderers:
            result = {
                "renderers": renderers,
                "animated": has_animator,
                "scripted": has_script,
                "prefab_name": os.path.splitext(os.path.basename(path))[0],
            }
    _PREFAB_SPRITE_CACHE[guid] = result
    return result


def extract_prefab_instances(docs, tex_index, prefab_index, props_out):
    """Static sprite prefabs become props (appended to props_out); animated or
    scripted prefabs (animals, VFX, managers) are listed for the manual pass."""
    _names, _comps, transforms, _t_of_go = build_maps(docs)
    manual = []
    auto = 0
    for anchor, (class_id, doc, _tag) in sorted(docs.items()):
        if class_id != CLASS_PREFAB_INSTANCE:
            continue
        mod = doc.get("m_Modification", {})
        guid = (doc.get("m_SourcePrefab") or {}).get("guid", "")
        pos = {"x": 0.0, "y": 0.0}
        name = ""
        for m in mod.get("m_Modifications") or []:
            prop = m.get("propertyPath", "")
            if prop == "m_LocalPosition.x":
                pos["x"] = float(m.get("value", 0) or 0)
            elif prop == "m_LocalPosition.y":
                pos["y"] = float(m.get("value", 0) or 0)
            elif prop == "m_Name" and not name:
                name = m.get("value", "")
        # the instance's local position is relative to its scene parent
        parent_t = (mod.get("m_TransformParent") or {}).get("fileID", 0)
        px, py, _psx, _psy = world_position_from_transform(transforms, parent_t or None)
        instance_pos = [round((pos["x"] + px) * PPU, 2),
                        round(-(pos["y"] + py) * PPU, 2)]
        info = prefab_root_sprite(prefab_index, guid)
        # Animated prefabs (Animator = animals, VFX) and sprite-less prefabs
        # (managers, lights) go to the manual list; scripted-but-static ones
        # (bushes, trees, lamps) are still emitted as props, tagged "scripted"
        # so behaviors (fader/rustle/light) can be attached in later phases.
        if info is None or info["animated"]:
            manual.append({
                "name": name or (info or {}).get("prefab_name", guid),
                "prefab_guid": guid,
                "prefab_name": (info or {}).get("prefab_name", ""),
                "animated": bool(info and info["animated"]),
                "scripted": bool(info and info["scripted"]),
                "position": instance_pos,
            })
            continue
        for r in info["renderers"]:
            resolved = resolve_sprite(tex_index, r["sprite_guid"], r["sprite_file_id"])
            if resolved is None:
                continue
            entry, rect, pivot, _physics = resolved
            ppu_scale = PPU / float(entry["parsed"]["ppu"] or PPU)
            lsx, lsy = r.get("local_scale", [1, 1])
            props_out.append({
                "name": name or info["prefab_name"],
                "prefab_name": info["prefab_name"],
                "scripted": info["scripted"],
                "position": [instance_pos[0] + r["local_offset"][0],
                             instance_pos[1] + r["local_offset"][1]],
                "scale": [round(lsx * ppu_scale, 4), round(lsy * ppu_scale, 4)],
                "texture": entry["rel"],
                "rect": rect,
                "pivot": pivot,
                "sorting_order": r["sorting_order"],
                "sorting_layer_id": 0,
                "flip_x": r["flip_x"],
                "flip_y": False,
            })
            auto += 1
    print(f"  {auto} prefab sprites -> props, {len(manual)} animated/scripted prefabs (manual pass)")
    return manual


def extract_crop_init(docs):
    beds = []
    for anchor, (class_id, doc, _tag) in docs.items():
        if class_id != CLASS_MONOBEHAVIOUR:
            continue
        if (doc.get("m_Script") or {}).get("guid") != CROP_INITIALIZER_GUID:
            continue
        for entry in doc.get("InitList") or []:
            cell = entry.get("Cell", {})
            crop_ref = entry.get("CropToPlant", {})
            beds.append({
                "cell": [cell.get("x", 0), -cell.get("y", 0) - 1],
                "crop_guid": crop_ref.get("guid", ""),
                "starting_stage": entry.get("StartingStage", 0),
            })
    print(f"  {len(beds)} crop-initializer beds")
    return beds


# ---------------------------------------------------------------- asset copy

def godot_art_path(unity_rel):
    """Assets/HappyHarvest/Art/Tiles/X/y.png -> art/tiles/x/y.png etc."""
    rel = unity_rel
    for prefix, repl in [
        ("Assets/HappyHarvest/Art/", "art/"),
        ("Assets/Enjin Integration/", "art/enjin/"),
        ("Assets/Free Game Items/", "art/enjin/free_game_items/"),
        ("Assets/Gems and gold/", "art/enjin/gems_and_gold/"),
        ("Assets/HappyHarvest/Audio/", "audio/"),
        ("Assets/HappyHarvest/Fonts/", "fonts/"),
    ]:
        if rel.startswith(prefix):
            rel = repl + rel[len(prefix):]
            break
    return snake(rel)


def copy_textures(tex_index, used_guids):
    mapping = {}
    for guid in sorted(used_guids):
        entry = tex_index.get(guid)
        if entry is None:
            continue
        dest_rel = godot_art_path(entry["rel"])
        dest = os.path.join(GODOT_ROOT, dest_rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(entry["png"], dest)
        mapping[entry["rel"]] = {
            "godot_path": "res://" + dest_rel,
            "size": list(texture_entry(tex_index, guid)["size"]),
        }
    print(f"copied {len(mapping)} textures -> art/")
    return mapping


def copy_blanket():
    """Audio, fonts, UI art, crop art, tool art, character/animal sheets."""
    jobs = [
        ("Assets/HappyHarvest/Audio", "audio"),
        ("Assets/HappyHarvest/Fonts", "fonts"),
        ("Assets/HappyHarvest/Art/UI", "art/ui"),
        ("Assets/HappyHarvest/Art/Crops", "art/crops"),
        ("Assets/HappyHarvest/Art/Tools", "art/tools"),
        ("Assets/HappyHarvest/Art/Animals", "art/animals"),
    ]
    copied = 0
    for src_rel, dest_rel in jobs:
        src_root = os.path.join(UNITY_ROOT, src_rel)
        if not os.path.isdir(src_root):
            print(f"  WARN: missing {src_rel}")
            continue
        for dirpath, _dirnames, filenames in os.walk(src_root):
            for fn in filenames:
                if fn.endswith(".meta") or fn.endswith(".mixer") or fn.endswith(".psd"):
                    continue
                if re.search(r"_(mask|normal)\.(png)$", fn, re.I):
                    continue  # URP normal/mask maps - unused in Godot GL compat
                if not re.search(r"\.(wav|ogg|mp3|png|ttf|otf|asset)$", fn, re.I):
                    continue
                if fn.endswith(".asset"):
                    continue
                src = os.path.join(dirpath, fn)
                rel_inside = os.path.relpath(src, src_root)
                dest = os.path.join(GODOT_ROOT, dest_rel, snake(rel_inside))
                os.makedirs(os.path.dirname(dest), exist_ok=True)
                shutil.copy2(src, dest)
                copied += 1
    print(f"copied {copied} blanket assets (audio/fonts/ui/crops/tools/animals)")


# ----------------------------------------------------------------------- main

def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print("indexing textures...")
    tex_index = index_textures()
    print(f"  {len(tex_index)} textures indexed")
    prefab_index = index_prefabs()
    print(f"  {len(prefab_index)} prefabs indexed")

    used_guids = set()
    for scene_name, scene_rel in SCENES.items():
        print(f"parsing {scene_rel} ...")
        docs = parse_scene(os.path.join(UNITY_ROOT, scene_rel))
        print(f"  {len(docs)} yaml documents")
        tile_objects = []
        tile_physics = {}
        layers = extract_tilemaps(docs, tex_index, scene_name, prefab_index,
                                  tile_objects, tile_physics)
        if tile_physics:
            print(f"  {len(tile_physics)} distinct tiles carry collision polygons")
            with open(os.path.join(OUT_DIR, f"{scene_name}_tile_physics.json"), "w") as f:
                json.dump(tile_physics, f, indent=1)
        props = extract_props(docs, tex_index)
        prefabs = extract_prefab_instances(docs, tex_index, prefab_index, props)
        # Tile-placed prefabs (fences): emit as props at the cell center and
        # keep the raw cell list for the collision pass.
        for to in tile_objects:
            info = prefab_root_sprite(prefab_index, to["prefab_guid"])
            if not info or info["animated"]:
                continue
            cx = to["cell"][0] * PPU + PPU / 2
            cy = to["cell"][1] * PPU + PPU / 2
            for r in info["renderers"]:
                resolved = resolve_sprite(tex_index, r["sprite_guid"], r["sprite_file_id"])
                if resolved is None:
                    continue
                entry, rect, pivot, _physics = resolved
                ppu_scale = PPU / float(entry["parsed"]["ppu"] or PPU)
                lsx, lsy = r.get("local_scale", [1, 1])
                props.append({
                    "name": info["prefab_name"],
                    "position": [round(cx + r["local_offset"][0], 2),
                                 round(cy + r["local_offset"][1], 2)],
                    "scale": [round(lsx * ppu_scale, 4), round(lsy * ppu_scale, 4)],
                    "texture": entry["rel"],
                    "rect": rect,
                    "pivot": pivot,
                    "sorting_order": r["sorting_order"],
                    "sorting_layer_id": 0,
                    "flip_x": r["flip_x"],
                    "flip_y": False,
                })
            to["prefab_name"] = info["prefab_name"]
        if tile_objects:
            print(f"  {len(tile_objects)} tile-object cells (fences) -> props + cell dump")
            with open(os.path.join(OUT_DIR, f"{scene_name}_tile_objects.json"), "w") as f:
                json.dump(tile_objects, f, indent=1)
        if scene_name == "farm_outdoor":
            crop_init = extract_crop_init(docs)
            with open(os.path.join(OUT_DIR, "crop_init.json"), "w") as f:
                json.dump(crop_init, f, indent=1)

        # collect texture guids used (back-resolve via rel path)
        rels = {c["texture"] for l in layers for c in l["cells"]}
        rels |= {p["texture"] for p in props}
        for guid, entry in tex_index.items():
            if entry["rel"] in rels:
                used_guids.add(guid)

        with open(os.path.join(OUT_DIR, f"{scene_name}.json"), "w") as f:
            json.dump(layers, f, indent=1)
        with open(os.path.join(OUT_DIR, f"{scene_name}_props.json"), "w") as f:
            json.dump(props, f, indent=1)
        with open(os.path.join(OUT_DIR, f"{scene_name}_prefabs.json"), "w") as f:
            json.dump(prefabs, f, indent=1)

    mapping = copy_textures(tex_index, used_guids)
    with open(os.path.join(OUT_DIR, "textures.json"), "w") as f:
        json.dump(mapping, f, indent=1)
    copy_blanket()
    print("done.")


if __name__ == "__main__":
    main()
