# Port of HappyHarvest.EnjinIntegration.Data.EnjinItem
# (Assets/Enjin Integration/Scripts/Data/EnjinItem.cs).
#
# Extends the game's base Item resource (scripts/game/items/item.gd), exactly
# like the Unity class extends the Item ScriptableObject. Existing .tres
# assets keep working: the script path and all property names are unchanged.

@tool
class_name EnjinItem
# extends by path, not by the `Item` global class name: this script is loaded
# while autoloads initialize (EnjinManager catalog), before the global class
# cache is ready, and a class-name extends fails to compile there
extends "res://scripts/game/items/item.gd"

# Collection id is stamped by the editor plugin from the running server's
# /api/setup/collection-id endpoint. -1 is a placeholder that means "not yet
# stamped" -- the EnjinManager will refuse to match wallet tokens against it.
@export var collection_id: String = "-1"
@export var token_id: String = "-1"

# Drop gate used by EnjinManager.randomly_reveal_token's re-roll, mirroring
# the rarity field on Unity's EnjinToken world prefab. Unity convention:
# the roll succeeds when randf() > rarity, so HIGHER means RARER.
@export_range(0.0, 1.0) var rarity: float = 0.0


func can_use(_target: Vector2i) -> bool:
    return true


func use(_target: Vector2i) -> bool:
    return true


# Fire-and-forget wrappers around EnjinManager. UI refresh is signal-driven
# (EnjinManager.wallet_updated) so callers don't need to await these.

func transfer(recipient: String, amount: int = 1) -> void:
    print("[EnjinItem] Transferring %d of token #%s" % [amount, token_id])
    await EnjinManager.transfer_token(token_id, amount, recipient)


func melt(amount: int = 1) -> void:
    print("[EnjinItem] Melting %d of token #%s" % [amount, token_id])
    await EnjinManager.melt_token(token_id, amount)


func collect() -> void:
    print("[EnjinItem] Collecting token #%s" % token_id)
    await EnjinManager.mint_token(token_id, 1)
