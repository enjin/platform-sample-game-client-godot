# A revealed token sitting in the world. Port of EnjinToken.cs: click it (or
# walk over it) to collect, which fire-and-forget mints the token to the
# player's managed wallet. Destruction on collect is intentional even if the
# mint fails (matching the Unity comment).
extends Area2D

@export var item: EnjinItem
# drop gate read by EnjinManager.randomly_reveal_token's re-roll;
# Unity convention: roll passes when randf() > rarity (higher = rarer)
@export_range(0.0, 1.0) var rarity: float = 0.0

var _collected := false
# The left-click that revealed this token (via the Hoe's "interact" use) is
# replayed onto us by the viewport's physics picking the instant we spawn under
# the cursor, which would collect the coin on that same click. Require the
# button to be released first so picking up needs a separate, fresh click.
var _click_armed := false

@onready var sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	if item != null and item.item_sprite != null and sprite.texture == null:
		sprite.texture = item.item_sprite
	input_pickable = true
	input_event.connect(_on_input_event)
	body_entered.connect(_on_body_entered)
	# gentle bob so it reads as a pickup
	var tween := create_tween().set_loops()
	tween.tween_property(sprite, "position:y", -6.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(sprite, "position:y", 0.0, 0.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(_delta: float) -> void:
	# Arm once the revealing click has been released; stop processing afterward.
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_click_armed = true
		set_process(false)


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not _click_armed:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		collect()


func _on_body_entered(body: Node2D) -> void:
	if body == GameManager.player:
		collect()


func collect() -> void:
	if _collected or item == null:
		return
	_collected = true
	item.collect()  # fire-and-forget mint; wallet_updated refreshes UI
	if has_node("/root/SoundManager"):
		var pickup: AudioStream = load("res://audio/planting/picking_up_crop.wav")
		get_node("/root/SoundManager").play_sfx_at(global_position, pickup)
	queue_free()


# IEnjinToken parity
func melt(amount: int = 1) -> void:
	if item:
		item.melt(amount)


func transfer(recipient: String, amount: int = 1) -> void:
	if item:
		item.transfer(recipient, amount)
