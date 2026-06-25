# In-game HUD: 9 inventory slots, coins, clock, backpack. Reproduces the Unity
# UI Toolkit overlay (GameUI.uxml / UIHandler.cs): coin pill top-left, clock
# pill, backpack sprite button top-right, Sprite_Target hotbar slots with a
# circle count badge and Q/E key hints on the end slots.
extends CanvasLayer

const SLOT_SIZE := 80
const GameManagerScript := preload("res://scripts/game/game_manager.gd")
const SLOT_TEX := preload("res://art/ui/sprite_target.png")
const SLOT_TEX_SELECTED := preload("res://art/ui/sprite_target_selected.png")
const BADGE_TEX := preload("res://art/ui/sprite_circle.png")
const KEY_TEX := preload("res://art/ui/sprite_keyboard_key.png")
const HUD_FONT := preload("res://fonts/cursecasual/curse_casual.ttf")
# Unity tints the un-equipped slot background to 31% alpha (Sprite_Target),
# equipped slots show the full-opacity Sprite_Target_selected.
const SLOT_DIM := 0.31

var _slots: Array[TextureButton] = []
var _icons: Array[TextureRect] = []
var _counts: Array[Label] = []
var _badges: Array[Control] = []

@onready var slot_row: HBoxContainer = %SlotRow
@onready var coins_label: Label = %CoinsLabel
@onready var clock_label: Label = %ClockLabel
@onready var backpack_button: BaseButton = %BackpackButton
@onready var backpack: Control = %Backpack
@onready var settings_button: Button = %SettingsButton
@onready var market_popup: Control = %MarketPopup
@onready var warehouse_popup: Control = %WarehousePopup
@onready var settings_popup: Control = %SettingsPopup
@onready var weather_block: Panel = %WeatherBlock
@onready var sun_button: Button = %SunButton
@onready var rain_button: Button = %RainButton
@onready var thunder_button: Button = %ThunderButton


func _ready() -> void:
	for i in InventorySystem.SIZE:
		var slot := TextureButton.new()
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.texture_normal = SLOT_TEX
		slot.ignore_texture_size = true
		slot.stretch_mode = TextureButton.STRETCH_SCALE
		slot.self_modulate = Color(1, 1, 1, SLOT_DIM)
		slot.focus_mode = Control.FOCUS_NONE
		slot.pressed.connect(_on_slot_pressed.bind(i))

		# the item sprite, inset to sit inside the slot frame (Unity Item)
		var icon := TextureRect.new()
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 11
		icon.offset_top = 1
		icon.offset_right = -11
		icon.offset_bottom = -9
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(icon)

		# stack-count badge: white circle sprite at the bottom-right corner
		var badge := TextureRect.new()
		badge.texture = BADGE_TEX
		badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		badge.stretch_mode = TextureRect.STRETCH_SCALE
		badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		badge.offset_left = -28
		badge.offset_top = -28
		badge.offset_right = 2
		badge.offset_bottom = 2
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.visible = false
		var count := Label.new()
		count.set_anchors_preset(Control.PRESET_FULL_RECT)
		count.add_theme_font_override("font", HUD_FONT)
		count.add_theme_font_size_override("font_size", 18)
		count.add_theme_color_override("font_color", Color.BLACK)
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_child(count)
		slot.add_child(badge)

		# Q / E quick-swap hints on the first and last slots (Unity Previous)
		if i == 0 or i == InventorySystem.SIZE - 1:
			var key := TextureRect.new()
			key.texture = KEY_TEX
			key.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			key.stretch_mode = TextureRect.STRETCH_SCALE
			key.custom_minimum_size = Vector2(30, 30)
			key.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if i == 0:
				key.set_anchors_preset(Control.PRESET_TOP_LEFT)
				key.offset_left = -20
				key.offset_top = -20
				key.offset_right = 10
				key.offset_bottom = 10
			else:
				key.set_anchors_preset(Control.PRESET_TOP_RIGHT)
				key.offset_left = -10
				key.offset_top = -20
				key.offset_right = 20
				key.offset_bottom = 10
			var key_label := Label.new()
			key_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			key_label.add_theme_font_override("font", HUD_FONT)
			key_label.add_theme_font_size_override("font_size", 20)
			key_label.add_theme_color_override("font_color", Color.BLACK)
			key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			key_label.text = "Q" if i == 0 else "E"
			key_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			key.add_child(key_label)
			slot.add_child(key)

		slot_row.add_child(slot)
		_slots.append(slot)
		_icons.append(icon)
		_counts.append(count)
		_badges.append(badge)

	backpack_button.pressed.connect(backpack.toggle)
	settings_button.pressed.connect(settings_popup.open)
	# let world objects (MarketStall/Warehouse) reach these popups
	GameManager.market_ui = market_popup
	GameManager.warehouse_ui = warehouse_popup
	# weather toggle (Unity's ☀/⛆/⛈ WeatherBlock under the clock). Thunder is
	# rain+thunder so it shows the storm, matching the weather elements' masks.
	sun_button.pressed.connect(_set_weather.bind(WeatherSystem.SUN))
	rain_button.pressed.connect(_set_weather.bind(WeatherSystem.RAIN))
	thunder_button.pressed.connect(
		_set_weather.bind(WeatherSystem.RAIN | WeatherSystem.THUNDER))
	_setup_weather.call_deferred()
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
		# stack count badge only shows when there is more than one
		var stacked: bool = entry.item != null and entry.stack_size > 1
		_badges[i].visible = stacked
		if stacked:
			_counts[i].text = str(entry.stack_size)
		# equipped slot: bright full-opacity selected frame; others dimmed
		var equipped: bool = i == inventory.equipped_index
		_slots[i].texture_normal = SLOT_TEX_SELECTED if equipped else SLOT_TEX
		_slots[i].self_modulate = Color.WHITE if equipped else Color(1, 1, 1, SLOT_DIM)


func _update_coins(amount: int) -> void:
	coins_label.text = str(amount)


# --------------------------------------------------------------- weather

# Hidden in scenes without a WeatherSystem (e.g. the house), like Unity which
# collapses the WeatherBlock when GameManager.WeatherSystem is null.
func _setup_weather() -> void:
	var weather = GameManager.weather
	weather_block.visible = weather != null
	if weather == null:
		return
	if not weather.weather_changed.is_connected(_update_weather_icons):
		weather.weather_changed.connect(_update_weather_icons)
	_update_weather_icons(weather.current)


func _set_weather(mask: int) -> void:
	if GameManager.weather:
		GameManager.weather.change_weather(mask)


func _update_weather_icons(mask: int) -> void:
	var is_thunder: bool = mask & WeatherSystem.THUNDER != 0
	var is_rain: bool = (mask & WeatherSystem.RAIN != 0) and not is_thunder
	var is_sun: bool = not is_rain and not is_thunder
	var dim := Color(1, 1, 1, 0.45)
	sun_button.modulate = Color.WHITE if is_sun else dim
	rain_button.modulate = Color.WHITE if is_rain else dim
	thunder_button.modulate = Color.WHITE if is_thunder else dim


var _last_clock := ""
func _update_clock(ratio: float) -> void:
	var text := GameManagerScript.get_time_as_string(ratio)
	if text != _last_clock:
		_last_clock = text
		clock_label.text = text
