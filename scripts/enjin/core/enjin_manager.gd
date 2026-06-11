# Port of HappyHarvest.EnjinIntegration.Core.EnjinManager
# (Assets/Enjin Integration/Scripts/Core/EnjinManager.cs).
#
# Owns the player's auth token (persisted to user://enjin.cfg), exposes
# wallet/mint/melt/transfer convenience methods that wrap EnjinApiService,
# and broadcasts signals so UI can react to login state + wallet refreshes.
#
# Also owns the in-game token catalog: a configurable list of EnjinItem
# resources that act as the bridge between on-chain tokens (collection_id +
# token_id) and in-game visuals (item.visual_prefab). The Unity version
# stored this on the EnjinManager prefab via [SerializeField]; here we
# load the .tres files from `res://resources/items/` on startup. Override
# `blockchain_tokens` from code/scene to customise.
#
# Autoloaded as `EnjinManager` (see project.godot).

extends Node

signal login_complete(success: bool)
signal logout_complete(success: bool)
signal wallet_updated()

const _TOKEN_CONFIG_PATH := "user://enjin.cfg"
const _TOKEN_CONFIG_SECTION := "auth"
const _TOKEN_CONFIG_KEY := "player_auth_token"

# Default catalog. Path-driven so the editor can ship more items without
# touching code; any EnjinItem .tres under res://resources/items/ shows up.
const _DEFAULT_ITEM_PATHS := [
    "res://resources/items/gem_green.tres",
    "res://resources/items/gold_coin.tres",
    "res://resources/items/gold_coin_blue.tres",
]

# Probability gate for harvest-time token reveals. Lower = more frequent.
# Matches `tokenRevealProbabilityThreshold` on the Unity prefab.
@export_range(0.0, 1.0) var token_reveal_probability_threshold: float = 0.5

# In-game tokens this client knows how to display + mint. Populated in
# _ready() from _DEFAULT_ITEM_PATHS; can be replaced before _ready by code
# that wants a custom catalog.
var blockchain_tokens: Array[EnjinItem] = []

# Latest filtered wallet snapshot. UI reads this directly; refresh via
# `await get_managed_wallet_tokens()` to repopulate and fire wallet_updated.
var wallet_account: PlatformModels.ManagedWalletAccount = null

var _auth_token: String = ""


func _ready() -> void:
    _load_token_from_disk()
    if blockchain_tokens.is_empty():
        for path in _DEFAULT_ITEM_PATHS:
            if ResourceLoader.exists(path):
                var item: Resource = load(path)
                if item is EnjinItem:
                    blockchain_tokens.append(item)
                else:
                    push_warning("[EnjinManager] %s did not load as EnjinItem; skipping." % path)
    # Prime the wallet cache so the backpack has something to show the first
    # time the player opens it. Fire-and-forget.
    get_managed_wallet_tokens()


# -------------------------- Auth --------------------------

func is_logged_in() -> bool:
    return not _auth_token.is_empty()


# Mirrors RegisterAndLogin(email, password) in the Unity port: the server
# endpoint registers-or-logs-in and returns a bearer token in either case.
func register_and_login(email: String, password: String) -> void:
    print("[EnjinManager] Attempting login for: %s" % email)
    var token := await EnjinApiService.login_user(email, password)
    if token.is_empty():
        push_error("[EnjinManager] Login failed.")
        login_complete.emit(false)
        return
    _auth_token = token
    _save_token_to_disk()
    print("[EnjinManager] Login successful.")
    login_complete.emit(true)
    # Prime wallet cache for the freshly-authenticated session.
    get_managed_wallet_tokens()


func logout() -> void:
    print("[EnjinManager] Logging out.")
    _auth_token = ""
    wallet_account = null
    var cfg := ConfigFile.new()
    # Re-write with an empty token rather than deleting the file so we keep
    # any future preferences in there. Match the Unity behaviour exactly.
    cfg.set_value(_TOKEN_CONFIG_SECTION, _TOKEN_CONFIG_KEY, "")
    cfg.save(_TOKEN_CONFIG_PATH)
    logout_complete.emit(true)


# -------------------------- Wallet --------------------------

# Pulls the full wallet from the server and filters it down to the
# collection_id + token_id pairs we know how to render (the catalog above).
# Sets `wallet_account` and emits `wallet_updated`.
func get_managed_wallet_tokens() -> void:
    if not is_logged_in():
        return
    var all := await EnjinApiService.get_managed_wallet_tokens(_auth_token)
    if all == null:
        # API service already logged the failure; surface an empty wallet so
        # callers don't have to null-check.
        wallet_account = PlatformModels.ManagedWalletAccount.new()
        wallet_updated.emit()
        return

    # Build lookup of (collection_id, token_id) string pairs we recognise.
    # Reminder: collection_id is stamped via the editor plugin's
    # "Stamp Collection ID onto EnjinItem Assets" action against the
    # running server's /api/setup/collection-id endpoint.
    var known := {}
    for item in blockchain_tokens:
        if item == null:
            continue
        known[_id_key(item.collection_id, item.token_id)] = true

    var filtered: Array = []
    for ta in all.token_accounts:
        if ta == null or ta.token == null:
            continue
        var cid: String = "" if ta.token.collection == null else ta.token.collection.collection_id
        var tid: String = ta.token.token_id
        if known.has(_id_key(cid, tid)):
            filtered.append(ta)

    var snapshot := PlatformModels.ManagedWalletAccount.new()
    snapshot.account = all.account
    snapshot.token_accounts = filtered
    wallet_account = snapshot
    wallet_updated.emit()


func mint_token(token_id: String, amount: int) -> void:
    if not is_logged_in():
        return
    var success := await EnjinApiService.mint_token(_auth_token, token_id, amount)
    if success:
        wallet_updated.emit()


func melt_token(token_id: String, amount: int) -> void:
    if not is_logged_in():
        return
    var success := await EnjinApiService.melt_token(_auth_token, token_id, amount)
    if success:
        wallet_updated.emit()


func transfer_token(token_id: String, amount: int, recipient: String) -> void:
    if not is_logged_in():
        return
    var success := await EnjinApiService.transfer_token(_auth_token, token_id, amount, recipient)
    if success:
        wallet_updated.emit()


# Returns the EnjinItem in the catalog matching the given (collection, token)
# pair, or null if we don't have one configured.
func get_token(collection_id: String, token_id: String) -> EnjinItem:
    for item in blockchain_tokens:
        if item == null:
            continue
        if item.collection_id == collection_id and item.token_id == token_id:
            return item
    return null


# Spawn a random token visual at the given WORLD position (px) with
# probability driven by the global threshold plus the per-token rarity
# re-roll, matching Unity EnjinManager.RandomlyRevealToken's do/while.
# Called by Hoe.use with terrain.map_to_local(cell) - tilling is the reveal
# hook in the Unity sample, not harvesting.
func randomly_reveal_token(world_pos: Vector2) -> void:
    if blockchain_tokens.is_empty():
        return
    if not _roll(token_reveal_probability_threshold):
        return
    # Re-roll which token until its rarity gate passes (same inverted
    # convention as the threshold: higher rarity = less likely).
    var item: EnjinItem = null
    var attempts := 0
    while attempts < 16:
        attempts += 1
        var candidate: EnjinItem = blockchain_tokens.pick_random()
        if candidate == null or candidate.visual_prefab == null:
            continue
        if _roll(candidate.rarity):
            item = candidate
            break
    if item == null:
        return
    var inst: Node = item.visual_prefab.instantiate()
    # tokens share the generic enjin_token.tscn; hand it the rolled item
    # (an item->scene->item reference cycle in the .tres would not load)
    if "item" in inst:
        inst.item = item
    if inst is Node2D:
        (inst as Node2D).global_position = world_pos
    get_tree().current_scene.add_child(inst)
    print("[EnjinManager] Revealed token: %s" % item.display_name)


# -------------------------- Helpers --------------------------

func _roll(threshold: float) -> bool:
    # Match the Unity semantics: returns true when randf > threshold, i.e.
    # higher threshold => less likely to fire. Counter-intuitive but kept
    # for parity so designers' tuned values port across unchanged.
    return randf() > threshold


func _id_key(collection_id: String, token_id: String) -> String:
    return "%s|%s" % [collection_id, token_id]


func _save_token_to_disk() -> void:
    if _auth_token.is_empty():
        return
    var cfg := ConfigFile.new()
    cfg.set_value(_TOKEN_CONFIG_SECTION, _TOKEN_CONFIG_KEY, _auth_token)
    var err := cfg.save(_TOKEN_CONFIG_PATH)
    if err != OK:
        push_error("[EnjinManager] Failed to save auth token (err %s)" % err)
    else:
        print("[EnjinManager] Token saved to %s" % _TOKEN_CONFIG_PATH)


func _load_token_from_disk() -> void:
    var cfg := ConfigFile.new()
    var err := cfg.load(_TOKEN_CONFIG_PATH)
    if err != OK:
        # No file yet -- first launch on this machine -- nothing to load.
        return
    _auth_token = cfg.get_value(_TOKEN_CONFIG_SECTION, _TOKEN_CONFIG_KEY, "")
    if not _auth_token.is_empty():
        print("[EnjinManager] Loaded saved auth token.")
