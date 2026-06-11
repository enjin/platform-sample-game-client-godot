# In-game HUD: 9 inventory slots, coins, clock. Control redesign of the
# Unity UIToolkit overlay (UIHandler.cs inventory/coin/time bindings).
extends CanvasLayer

const SLOT_SIZE := 76

var _slots: Array[Button] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []

@onready var slot_row: HBoxContainer = %SlotRow
@onready var coins_label: Label = %CoinsLabel
@onready var clock_label: Label = %ClockLabel
@onready var backpack_button: Button = %BackpackButton
@onready var backpack: Control = %Backpack


func _ready() -> void:
	for i in InventorySystem.SIZE:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.toggle_mode = false
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(_on_slot_pressed.bind(i))
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 8
		icon.offset_top = 8
		icon.offset_right = -8
		icon.offset_bottom = -8
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)
		var count := Label.new()
		count.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		count.offset_left = -30
		count.offset_top = -26
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(count)
		slot_row.add_child(slot)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(count)

	backpack_button.pressed.connect(backpack.toggle)
	GameManager.coins_changed.connect(_update_coins)
	GameManager.day_ratio_changed.connect(_update_clock)
	var inventory: InventorySystem = GameManager.ensure_inventory()
	inventory.changed.connect(_update_inventory)
	_update_inventory()
	_update_coins(GameManager.coins)
	_update_clock(GameManager.current_day_ratio)


func _on_slot_pressed(index: int) -> void:
	if GameManager.player:
		GameManager.player.change_equip_item(index)


func _update_inventory() -> void:
	var inventory: InventorySystem = GameManager.inventory
	if inventory == null:
		return
	for i in InventorySystem.SIZE:
		var entry = inventory.entries[i]
		_icons[i].texture = entry.item.item_sprite if entry.item else null
		_counts[i].text = str(entry.stack_size) if entry.stack_size > 1 else ""
		# highlight the equipped slot
		_slots[i].modulate = Color(1, 1, 0.6) if i == inventory.equipped_index \
			else Color.WHITE


func _update_coins(amount: int) -> void:
	coins_label.text = str(amount)


var _last_clock := ""
func _update_clock(ratio: float) -> void:
	var text := GameManager.get_time_as_string(ratio)
	if text != _last_clock:
		_last_clock = text
		clock_label.text = text
