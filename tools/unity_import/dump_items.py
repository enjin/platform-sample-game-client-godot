#!/usr/bin/env python3
"""Dump HappyHarvest item/product/crop ScriptableObjects to JSON with asset
references resolved to Godot res:// paths. Consumed by build_items.gd."""

import glob
import json
import os
import re

import yaml

try:
    from yaml import CSafeLoader as SafeLoader
except ImportError:
    from yaml import SafeLoader

from extract_unity_maps import (GODOT_ROOT, UNITY_ROOT, find_normal_map,
                                godot_art_path, index_prefabs, index_textures,
                                prefab_root_sprite, resolve_sprite)

OUT = os.path.join(GODOT_ROOT, "tools/unity_import/out/items.json")

SCRIPT_GUIDS = {}  # guid -> class name (Hoe, WaterCan, ...)
for cs in glob.glob(os.path.join(UNITY_ROOT, "Assets/HappyHarvest/Scripts/Items/*.cs")) + \
        glob.glob(os.path.join(UNITY_ROOT, "Assets/HappyHarvest/Scripts/Crop.cs")):
    meta = cs + ".meta"
    if os.path.exists(meta):
        with open(meta) as f:
            m = re.search(r"guid: ([0-9a-f]{32})", f.read())
        if m:
            SCRIPT_GUIDS[m.group(1)] = os.path.splitext(os.path.basename(cs))[0]


def index_guids(pattern, root=UNITY_ROOT):
    out = {}
    for meta in glob.glob(os.path.join(root, pattern), recursive=True):
        with open(meta) as f:
            m = re.search(r"guid: ([0-9a-f]{32})", f.read(300))
        if m:
            out[m.group(1)] = meta[: -len(".meta")]
    return out


def load_asset(path):
    with open(path) as f:
        text = f.read()
    body = text[text.index("MonoBehaviour:"):]
    return yaml.load(body, Loader=SafeLoader)["MonoBehaviour"]


def main():
    tex_index = index_textures()
    audio_index = index_guids("Assets/HappyHarvest/Audio/**/*.wav.meta")
    tile_assets = index_guids("Assets/HappyHarvest/Art/**/*.asset.meta")
    prefab_index = index_prefabs()

    def sprite_ref(ref):
        if not ref or not ref.get("guid"):
            return None
        resolved = resolve_sprite(tex_index, ref["guid"], ref.get("fileID", 0))
        if resolved is None:
            return None
        entry, rect, _pivot, _phys = resolved
        ref_out = {"texture": "res://" + godot_art_path(entry["rel"]), "rect": rect,
                   "ppu": entry["parsed"]["ppu"]}
        normal = find_normal_map(entry["png"])
        if normal:
            dest_rel = godot_art_path(entry["rel"])[:-len(".png")] + "_normal.png"
            dest = os.path.join(GODOT_ROOT, dest_rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            import shutil
            shutil.copy2(normal, dest)
            ref_out["normal"] = "res://" + dest_rel
        return ref_out

    def audio_ref(ref):
        if not ref or not ref.get("guid") or ref["guid"] not in audio_index:
            return None
        rel = os.path.relpath(audio_index[ref["guid"]], UNITY_ROOT)
        return "res://" + godot_art_path(rel)

    def tile_sprite(ref):
        """Crop growth stages are RuleTile assets whose visual is a prefab
        (m_DefaultGameObject) with a SpriteRenderer; m_DefaultSprite is unset."""
        if not ref or ref.get("guid") not in tile_assets:
            return None
        tile = load_asset(tile_assets[ref["guid"]])
        direct = sprite_ref(tile.get("m_DefaultSprite") or tile.get("m_Sprite"))
        if direct:
            return direct
        prefab_guid = (tile.get("m_DefaultGameObject") or {}).get("guid")
        if not prefab_guid:
            return None
        info = prefab_root_sprite(prefab_index, prefab_guid)
        if info and info["renderers"]:
            r = info["renderers"][0]
            return sprite_ref({"guid": r["sprite_guid"], "fileID": r["sprite_file_id"]})
        # prefab variants carry the sprite as an m_Sprite override on the
        # nested PrefabInstance rather than a direct SpriteRenderer
        from extract_unity_maps import parse_scene
        path = index_prefabs().get(prefab_guid)
        if not path:
            return None
        for _anchor, (class_id, doc, _tag) in parse_scene(path).items():
            if class_id != 1001:
                continue
            for m in (doc.get("m_Modification") or {}).get("m_Modifications") or []:
                if m.get("propertyPath") == "m_Sprite":
                    ref = m.get("objectReference") or {}
                    if ref.get("guid"):
                        return sprite_ref(ref)
        return None

    items = []
    for path in sorted(glob.glob(os.path.join(
            UNITY_ROOT, "Assets/HappyHarvest/Data/**/*.asset"), recursive=True)):
        if "Database" in path:
            continue
        a = load_asset(path)
        cls = SCRIPT_GUIDS.get((a.get("m_Script") or {}).get("guid", ""), "")
        if not cls:
            continue
        entry = {
            "class": cls,
            "name": a.get("m_Name", ""),
            "unique_id": a.get("UniqueID", ""),
        }
        if cls == "Crop":
            stages = [tile_sprite(t) for t in a.get("GrowthStagesTiles") or []]
            # Unity draws stage sprites at pixels/PPU units; our crop Sprite2Ds
            # are native-pixel, so they carry a 64/ppu scale
            ppu = next((s["ppu"] for s in stages if s), 100)
            entry.update({
                "growth_stages": stages,
                "stage_scale": round(64.0 / ppu, 4),
                "produce_id": "",  # filled below via guid map
                "produce_guid": (a.get("Produce") or {}).get("guid", ""),
                "growth_time": a.get("GrowthTime", 1.0),
                "number_of_harvest": a.get("NumberOfHarvest", 1),
                "stage_after_harvest": a.get("StageAfterHarvest", 1),
                "product_per_harvest": a.get("ProductPerHarvest", 1),
                "dry_death_timer": a.get("DryDeathTimer", 30.0),
            })
        else:
            entry.update({
                "display_name": a.get("DisplayName", ""),
                "item_sprite": sprite_ref(a.get("ItemSprite")),
                "max_stack_size": a.get("MaxStackSize", 10),
                "consumable": bool(a.get("Consumable", 1)),
                "buy_price": a.get("BuyPrice", -1),
                "animator_trigger": a.get("PlayerAnimatorTriggerUse", "GenericToolSwing"),
                "use_sounds": [s for s in map(audio_ref, a.get("UseSound") or []) if s],
            })
            if cls == "Product":
                entry["sell_price"] = a.get("SellPrice", 1)
            if cls == "SeedBag":
                entry["planted_crop_guid"] = (a.get("PlantedCrop") or {}).get("guid", "")
        # asset's own guid so crops/seedbags can cross-reference
        with open(path + ".meta") as f:
            entry["guid"] = re.search(r"guid: ([0-9a-f]{32})", f.read(300)).group(1)
        items.append(entry)

    with open(OUT, "w") as f:
        json.dump(items, f, indent=1)
    print(f"dumped {len(items)} assets -> {OUT}")
    for it in items:
        print(" ", it["class"], it["unique_id"])


if __name__ == "__main__":
    main()
