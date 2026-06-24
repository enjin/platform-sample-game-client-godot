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
SHADOW_PREFAB_GUID = "3154484e43d90644b8e969b02ef3a297"
PPU = 64  # spritePixelsToUnits everywhere in this project

CLASS_GAMEOBJECT = 1
CLASS_TRANSFORM = 4
CLASS_SPRITERENDERER = 212
CLASS_MONOBEHAVIOUR = 114
CLASS_TILEMAP = 1839735485
CLASS_TILEMAP_RENDERER = 483693784
CLASS_TILEMAP_COLLIDER = 19719996
CLASS_BOX_COLLIDER = 61
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


# ------------------------------------------------------------- tile collision
# Unity decides per-tile collision via each Tile/RuleTile asset's colliderType:
# 0 = None (no collision), 1 = Sprite (follow the sprite's opaque shape),
# 2 = Grid (full cell). A tile only collides if its TILEMAP also has a
# TilemapCollider2D (see has_collider). The sprite sheets here carry no custom
# physicsShape, so Sprite-type tiles (e.g. the house "walls" tilemap) produce
# NO collision unless we reconstruct it from the sprite alpha. Without this the
# player walks through walls.

COLLIDER_NONE, COLLIDER_SPRITE, COLLIDER_GRID = 0, 1, 2


def index_tile_collider_types():
    """guid -> collider type int, scanning Tile/RuleTile .asset files. A
    RuleTile mixes many per-rule types; collapse to 0 only when every type is
    0 (e.g. walkable dirt/grass), else Grid if any Grid, else Sprite."""
    result = {}
    root = os.path.join(UNITY_ROOT, "Assets/HappyHarvest")
    for dirpath, _dirnames, filenames in os.walk(root):
        for fn in filenames:
            if not fn.endswith(".asset"):
                continue
            apath = os.path.join(dirpath, fn)
            mpath = apath + ".meta"
            if not os.path.exists(mpath):
                continue
            with open(apath) as f:
                # Only the per-rule/plain m_ColliderType counts. RuleTiles also
                # carry m_DefaultColliderType (defaults to 1=Sprite, the
                # unmatched fallback); counting it would wrongly mark walkable
                # ground (dirt/grass, whose rules are all 0) as solid.
                types = [int(t) for t in re.findall(
                    r"(?<!Default)ColliderType:\s*(\d+)", f.read())]
            if not types:
                continue
            with open(mpath) as f:
                g = re.search(r"guid:\s*([0-9a-f]{32})", f.read(200))
            if not g:
                continue
            if all(t == 0 for t in types):
                ct = COLLIDER_NONE
            elif COLLIDER_GRID in types:
                ct = COLLIDER_GRID
            else:
                ct = COLLIDER_SPRITE
            result[g.group(1)] = ct
    return result


_alpha_image_cache = {}


def _full_cell_polygon(w, h):
    return [[-w / 2.0, -h / 2.0], [-w / 2.0, h / 2.0],
            [w / 2.0, h / 2.0], [w / 2.0, -h / 2.0]]


def _opaque_bbox_polygon(png_path, rect):
    """Tight bounding box of the sprite region's opaque (alpha>0) pixels, as a
    rectangle polygon in Godot tile-local space (center origin, y-down). None
    if Pillow is unavailable or the region is fully transparent."""
    try:
        from PIL import Image
    except ImportError:
        return None
    img = _alpha_image_cache.get(png_path)
    if img is None:
        img = Image.open(png_path).convert("RGBA")
        _alpha_image_cache[png_path] = img
    x, y, w, h = (int(rect[0]), int(rect[1]), int(rect[2]), int(rect[3]))
    alpha = img.crop((x, y, x + w, y + h)).getchannel("A")
    bbox = alpha.getbbox()  # (left, upper, right, lower); right/lower exclusive
    if bbox is None:
        return None
    l, u, r, lo = bbox
    left, right = l - w / 2.0, r - w / 2.0
    top, bottom = u - h / 2.0, lo - h / 2.0
    return [[round(left, 2), round(top, 2)], [round(left, 2), round(bottom, 2)],
            [round(right, 2), round(bottom, 2)], [round(right, 2), round(top, 2)]]


def tile_collision_shape(collider_type, png_path, rect):
    """Reconstruct a tile's collision (list of polygons) from its colliderType.
    Grid -> full cell; Sprite -> opaque alpha bbox (full cell if alpha read
    fails). Returns [] for None or an empty region."""
    w, h = int(rect[2]), int(rect[3])
    if collider_type == COLLIDER_GRID:
        return [_full_cell_polygon(w, h)]
    if collider_type == COLLIDER_SPRITE:
        poly = _opaque_bbox_polygon(png_path, rect)
        return [poly] if poly else [_full_cell_polygon(w, h)]
    return []


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


def color_of(doc):
    c = doc.get("m_Color") or {}
    return [round(c.get("r", 1), 4), round(c.get("g", 1), 4),
            round(c.get("b", 1), 4), round(c.get("a", 1), 4)]


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
                     tile_objects_out=None, tile_physics=None,
                     collider_types=None):
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
        # Unity sorting layer rank: Bottom=-1, Default=0, Objects=1,
        # ObjectsFront=2 (TagManager order). Objects+ draw above the ground.
        sorting_layer = 0
        has_collider = False
        box_colliders = []
        for cid, comp_anchor in go_components.get(go, []):
            if cid == CLASS_TILEMAP_RENDERER:
                sorting_order = docs[comp_anchor][1].get("m_SortingOrder", 0)
                sorting_layer = docs[comp_anchor][1].get("m_SortingLayer", 0)
            elif cid == CLASS_TILEMAP_COLLIDER:
                has_collider = True
            elif cid == CLASS_BOX_COLLIDER:
                box_colliders.append(docs[comp_anchor][1])
        sprite_array = doc.get("m_TileSpriteArray") or []
        tile_asset_array = doc.get("m_TileAssetArray") or []
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
            # Tile collision: a custom physicsShape (e.g. elevation cliffs) is
            # used verbatim; otherwise reconstruct from the tile's colliderType
            # (Sprite -> alpha bbox, Grid -> full cell). Purely additive: tiles
            # that emitted nothing before still emit nothing unless their
            # colliderType is Sprite/Grid (e.g. the house "walls").
            if has_collider:
                ctype = COLLIDER_NONE
                ti = td.get("m_TileIndex", 65535)
                if collider_types is not None and ti < len(tile_asset_array):
                    cg = (tile_asset_array[ti].get("m_Data") or {}).get("guid")
                    ctype = collider_types.get(cg, COLLIDER_NONE)
                shape = physics or tile_collision_shape(ctype, entry["png"], rect)
                if shape:
                    key = f"{entry['rel']}|{rect[0]}|{rect[1]}|{rect[2]}|{rect[3]}"
                    tile_physics[key] = shape
            cells.append({
                "x": ux0,
                "y": -uy0 - 1,  # unity y-up -> godot y-down
                "texture": entry["rel"],
                "rect": rect,
            })
        # BoxCollider2D on building tilemaps (House): center + size in godot px
        boxes = []
        for bc in box_colliders:
            off = bc.get("m_Offset", {"x": 0, "y": 0})
            size = bc.get("m_Size", {"x": 1, "y": 1})
            boxes.append({
                "center": [round((ox + off["x"]) * PPU, 2),
                           round(-(oy + off["y"]) * PPU, 2)],
                "size": [round(size["x"] * PPU, 2), round(size["y"] * PPU, 2)],
            })
        layers.append({
            "layer_name": name,
            "sorting_order": sorting_order,
            "sorting_layer": sorting_layer,
            "has_collider": has_collider,
            "box_colliders": boxes,
            "tile_anchor": [anchor_off.get("x", 0.5), anchor_off.get("y", 0.5)],
            "cells": cells,
        })
    layers.sort(key=lambda l: (l["sorting_layer"], l["sorting_order"]))
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
            "sorting_layer": doc.get("m_SortingLayer", 0),
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


def prefab_root_sprite(prefab_index, guid, _depth=0):
    """Resolve a prefab's visual: its root-most SpriteRenderer sprite ref,
    that renderer's sorting order, and whether the prefab is animated/scripted
    (Animator or MonoBehaviour present -> gameplay object, not a static prop).
    Prefab VARIANTS (a PrefabInstance wrapping a base prefab with an m_Sprite
    override - fences, crops, market...) resolve through their base.
    Returns dict or None."""
    if guid in _PREFAB_SPRITE_CACHE:
        return _PREFAB_SPRITE_CACHE[guid]
    if _depth > 4:
        return None
    path = prefab_index.get(guid)
    result = None
    if path and os.path.exists(path):
        docs = parse_scene(path)
        has_animator = any(cid == 95 for cid, _d, _t in docs.values())
        has_script = any(cid == CLASS_MONOBEHAVIOUR for cid, _d, _t in docs.values())
        renderers = []
        names, _comps, transforms, transform_of_go = build_maps(docs)
        # the prefab ROOT's scale applies to instances unless overridden
        # (its position does not - instances override that)
        root_scale = [1.0, 1.0]
        root_transform_id = 0
        for _ta, tdoc in transforms.items():
            if not tdoc.get("m_Father", {}).get("fileID", 0):
                ls = tdoc.get("m_LocalScale") or {}
                if ls:  # skip stripped/empty transform docs
                    root_scale = [ls.get("x", 1), ls.get("y", 1)]
                    root_transform_id = _ta
                    break
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
                "sorting_layer": doc.get("m_SortingLayer", 0),
                "color": color_of(doc),
                "flip_x": bool(doc.get("m_FlipX", 0)),
            })
        # Nested prefab instances (sofa pillows, decorations) compose into the
        # parent's renderer list with their position/color overrides applied.
        # Only for composite prefabs (with own renderers); renderer-less
        # wrappers are prefab VARIANTS handled in the else-branch below.
        if renderers:
            for _a, (cid2, doc2, tag2) in sorted(docs.items()):
                if tag2 != "PrefabInstance":
                    continue
                nested_guid = (doc2.get("m_SourcePrefab") or {}).get("guid")
                if not nested_guid or nested_guid == SHADOW_PREFAB_GUID:
                    continue
                nested = prefab_root_sprite(prefab_index, nested_guid, _depth + 1)
                if not nested:
                    continue
                mod2 = doc2.get("m_Modification") or {}
                mods2 = mod2.get("m_Modifications") or []
                vals = {m.get("propertyPath"): m.get("value") for m in mods2}
                nx = float(vals.get("m_LocalPosition.x", 0) or 0)
                ny = float(vals.get("m_LocalPosition.y", 0) or 0)
                # parent chain inside this prefab, excluding the prefab root
                px = py = 0.0
                t_anchor = (mod2.get("m_TransformParent") or {}).get("fileID", 0) or None
                guard = 0
                while t_anchor and guard < 64:
                    t = transforms.get(t_anchor)
                    if t is None:
                        break
                    father = t.get("m_Father", {}).get("fileID", 0)
                    if not father:
                        break
                    lp = t.get("m_LocalPosition", {})
                    px += lp.get("x", 0)
                    py += lp.get("y", 0)
                    t_anchor = father
                    guard += 1
                color_override = {}
                for m in mods2:
                    pp = str(m.get("propertyPath", ""))
                    if pp.startswith("m_Color."):
                        color_override[pp[-1]] = float(m.get("value", 1) or 0)
                nrs_x, nrs_y = nested.get("root_scale", [1, 1])
                # the nesting instance's own scale override replaces the
                # nested prefab's root scale (Unity semantics)
                if vals.get("m_LocalScale.x") is not None:
                    nrs_x = float(vals["m_LocalScale.x"] or 1)
                if vals.get("m_LocalScale.y") is not None:
                    nrs_y = float(vals["m_LocalScale.y"] or 1)
                for r in nested["renderers"]:
                    nr = dict(r)
                    nr["local_scale"] = [r.get("local_scale", [1, 1])[0] * nrs_x,
                                         r.get("local_scale", [1, 1])[1] * nrs_y]
                    nr["local_offset"] = [
                        round(r["local_offset"][0] * nrs_x + (nx + px) * PPU, 2),
                        round(r["local_offset"][1] * nrs_y - (ny + py) * PPU, 2)]
                    if color_override:
                        c = list(r.get("color", [1, 1, 1, 1]))
                        for i, ch in enumerate("rgba"):
                            if ch in color_override:
                                c[i] = round(color_override[ch], 4)
                        nr["color"] = c
                    renderers.append(nr)
            renderers.sort(key=lambda r: r.get("sorting_order", 0))

        # solid (non-trigger) colliders on the prefab: tree trunks, barrels...
        # offsets/sizes are unity units -> godot px (y-down)
        colliders = []
        for _a, (cid2, doc2, tag2) in docs.items():
            if tag2 not in ("BoxCollider2D", "CircleCollider2D"):
                continue
            if doc2.get("m_IsTrigger", 0):
                continue
            off = doc2.get("m_Offset", {})
            entry_c = {
                "type": "box" if tag2 == "BoxCollider2D" else "circle",
                "offset": [round(off.get("x", 0) * PPU, 2),
                           round(-off.get("y", 0) * PPU, 2)],
            }
            if tag2 == "BoxCollider2D":
                size = doc2.get("m_Size", {})
                entry_c["size"] = [round(size.get("x", 1) * PPU, 2),
                                   round(size.get("y", 1) * PPU, 2)]
            else:
                entry_c["radius"] = round(doc2.get("m_Radius", 0.5) * PPU, 2)
            colliders.append(entry_c)

        # nested Art/shadow.prefab instance = drop shadow rotated by the
        # day cycle in Unity (ShadowInstance + DayCycleHandler.UpdateShadow)
        shadow = None
        for _a, (cid2, doc2, tag2) in docs.items():
            if tag2 != "PrefabInstance":
                continue
            if (doc2.get("m_SourcePrefab") or {}).get("guid") != SHADOW_PREFAB_GUID:
                continue
            mods2 = (doc2.get("m_Modification") or {}).get("m_Modifications") or []
            vals = {m.get("propertyPath"): m.get("value") for m in mods2}
            shadow = {
                "offset": [round(float(vals.get("m_LocalPosition.x", 0) or 0) * PPU, 2),
                           round(-float(vals.get("m_LocalPosition.y", 0) or 0) * PPU, 2)],
                "scale": [round(float(vals.get("m_LocalScale.x", 1) or 1), 3),
                          round(float(vals.get("m_LocalScale.y", 1) or 1), 3)],
                "base_length": round(float(vals.get("BaseLength", 1) or 1), 3),
            }
            break
        if renderers:
            result = {
                "renderers": renderers,
                "root_scale": root_scale,
                "root_transform_id": root_transform_id,
                "shadow": shadow,
                "colliders": colliders,
                "animated": has_animator,
                "scripted": has_script,
                "prefab_name": os.path.splitext(os.path.basename(path))[0],
            }
        else:
            # prefab variant: resolve via the base prefab, apply the variant's
            # m_Sprite override, and inherit animated/scripted from the base
            for _anchor, (class_id, doc, _tag) in docs.items():
                if class_id != CLASS_PREFAB_INSTANCE:
                    continue
                base_guid = (doc.get("m_SourcePrefab") or {}).get("guid")
                if not base_guid:
                    continue
                base = prefab_root_sprite(prefab_index, base_guid, _depth + 1)
                if base is None:
                    continue
                sprite_override = None
                for m in (doc.get("m_Modification") or {}).get("m_Modifications") or []:
                    if m.get("propertyPath") == "m_Sprite":
                        ref = m.get("objectReference") or {}
                        if ref.get("guid"):
                            sprite_override = ref
                            break
                base_renderers = [dict(r) for r in base["renderers"]]
                if sprite_override and base_renderers:
                    base_renderers[0]["sprite_guid"] = sprite_override["guid"]
                    base_renderers[0]["sprite_file_id"] = sprite_override.get("fileID", 0)
                result = {
                    "renderers": base_renderers,
                    "animated": base["animated"] or has_animator,
                    "scripted": base["scripted"] or has_script,
                    "prefab_name": os.path.splitext(os.path.basename(path))[0],
                }
                break
    _PREFAB_SPRITE_CACHE[guid] = result
    return result


# Animated prefabs whose motion is decorative (sway/flap): a static prop
# beats a missing one. Animals are NOT here - a frozen chicken looks wrong.
STATIC_OK = {"Prefab_Market", "Prefab_Scarecow", "Prefab_Scarecow2",
             "log_horizontal", "log_vertical"}


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
        color_override = {}
        scale_override_targets = {}
        for m in mod.get("m_Modifications") or []:
            prop = m.get("propertyPath", "")
            if prop == "m_LocalPosition.x":
                pos["x"] = float(m.get("value", 0) or 0)
            elif prop == "m_LocalPosition.y":
                pos["y"] = float(m.get("value", 0) or 0)
            elif prop == "m_Name" and not name:
                name = m.get("value", "")
            elif prop.startswith("m_Color."):
                color_override[prop[-1]] = float(m.get("value", 1) or 0)
            elif prop == "m_LocalScale.x":
                scale_override_targets.setdefault(
                    (m.get("target") or {}).get("fileID", 0), [None, None])[0] = \
                    float(m.get("value", 1) or 1)
            elif prop == "m_LocalScale.y":
                scale_override_targets.setdefault(
                    (m.get("target") or {}).get("fileID", 0), [None, None])[1] = \
                    float(m.get("value", 1) or 1)
        # the instance's local position is relative to its scene parent
        parent_t = (mod.get("m_TransformParent") or {}).get("fileID", 0)
        px, py, _psx, _psy = world_position_from_transform(transforms, parent_t or None)
        instance_pos = [round((pos["x"] + px) * PPU, 2),
                        round(-(pos["y"] + py) * PPU, 2)]
        info = prefab_root_sprite(prefab_index, guid)
        scale_override = [None, None]
        if info:
            scale_override = scale_override_targets.get(
                info.get("root_transform_id", 0), [None, None])
        # Animated prefabs (Animator = animals, VFX) and sprite-less prefabs
        # (managers, lights) go to the manual list; scripted-but-static ones
        # (bushes, trees, lamps) are still emitted as props, tagged "scripted"
        # so behaviors (fader/rustle/light) can be attached in later phases.
        if info is None or (info["animated"]
                and info["prefab_name"] not in STATIC_OK):
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
            rsx, rsy = info.get("root_scale", [1, 1])
            if scale_override[0] is not None:
                rsx = scale_override[0]
            if scale_override[1] is not None:
                rsy = scale_override[1]
            lsx *= rsx
            lsy *= rsy
            color = list(r.get("color", [1, 1, 1, 1]))
            for i, ch in enumerate("rgba"):
                if ch in color_override:
                    color[i] = round(color_override[ch], 4)
            props_out.append({
                "name": name or info["prefab_name"],
                "prefab_name": info["prefab_name"],
                "scripted": info["scripted"],
                "shadow": info.get("shadow") if r is info["renderers"][0] else None,
                "colliders": ([{**c,
                    "offset": [c["offset"][0] * rsx, c["offset"][1] * rsy],
                    "size": [c["size"][0] * rsx, c["size"][1] * rsy] if "size" in c else None,
                    "radius": c.get("radius", 0) * rsx,
                } for c in info.get("colliders", [])]
                    if r is info["renderers"][0] else None),
                "color": color,
                "position": [instance_pos[0] + r["local_offset"][0] * rsx,
                             instance_pos[1] + r["local_offset"][1] * rsy],
                "scale": [round(lsx * ppu_scale, 4), round(lsy * ppu_scale, 4)],
                "texture": entry["rel"],
                "rect": rect,
                "pivot": pivot,
                "sorting_order": r["sorting_order"],
                "sorting_layer": r.get("sorting_layer", 0),
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


def find_normal_map(png_path):
    """Sibling normal map (`foo_normal.png` / `foo_n.png`) for a diffuse png."""
    base = png_path[:-len(".png")]
    for suffix in ("_normal.png", "_n.png"):
        candidate = base + suffix
        if os.path.exists(candidate):
            return candidate
    return None


def copy_textures(tex_index, used_guids):
    mapping = {}
    normals = 0
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
        normal = find_normal_map(entry["png"])
        if normal:
            normal_rel = dest_rel[:-len(".png")] + "_normal.png"
            shutil.copy2(normal, os.path.join(GODOT_ROOT, normal_rel))
            mapping[entry["rel"]]["normal"] = "res://" + normal_rel
            normals += 1
    print(f"copied {len(mapping)} textures ({normals} with normal maps) -> art/")
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
    collider_types = index_tile_collider_types()
    print(f"  {len(collider_types)} tile assets indexed for collider type")

    used_guids = set()
    for scene_name, scene_rel in SCENES.items():
        print(f"parsing {scene_rel} ...")
        docs = parse_scene(os.path.join(UNITY_ROOT, scene_rel))
        print(f"  {len(docs)} yaml documents")
        tile_objects = []
        tile_physics = {}
        layers = extract_tilemaps(docs, tex_index, scene_name, prefab_index,
                                  tile_objects, tile_physics, collider_types)
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
            if not info or (info["animated"]
                    and info["prefab_name"] not in STATIC_OK):
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
                    "color": r.get("color", [1, 1, 1, 1]),
                    "position": [round(cx + r["local_offset"][0], 2),
                                 round(cy + r["local_offset"][1], 2)],
                    "scale": [round(lsx * ppu_scale, 4), round(lsy * ppu_scale, 4)],
                    "texture": entry["rel"],
                    "rect": rect,
                    "pivot": pivot,
                    "sorting_order": r["sorting_order"],
                    "sorting_layer": r.get("sorting_layer", 0),
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
