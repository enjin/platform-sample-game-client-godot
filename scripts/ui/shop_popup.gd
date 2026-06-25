# Base for the Market and Warehouse popups (Unity's MarketPopup/WarehousePopup
# in GameUI.uxml + UIHandler/WarehouseUI). A centered blue rounded panel with a
# title, two tabs, a scrolling row list and a close X. Subclasses set the title
# and tab labels and fill each tab via _populate_left/_populate_right.
extends Control

const HUD_FONT := preload("res://fonts/cursecasual/curse_casual.ttf")
const MAIN_COLOR := Color(0, 0.498, 0.886)        # rgb(0,127,226)
const ROW_NAME_COLOR := Color(0, 0.345, 0.612)    # rgb(0,88,156)

var _content: VBoxContainer
var _left_tab: Button
var _right_tab: Button
var _title_label: Label
var _showing_left := true


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


# ---- subclass hooks ----
func _title() -> String: return "Shop"
func _left_text() -> String: return "Left"
func _right_text() -> String: return "Right"
func _populate_left() -> void: pass
func _populate_right() -> void: pass
# Whether the left tab is the default shown on open.
func _open_on_left() -> bool: return true


func _build() -> void:
	# transparent click-catcher behind the panel: closing on outside click,
	# matching Unity's capture-phase outside-click dismiss.
	var catcher := Button.new()
	catcher.flat = true
	catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	catcher.focus_mode = Control.FOCUS_NONE
	catcher.pressed.connect(close)
	add_child(catcher)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(500, 860)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -430
	panel.offset_bottom = 430
	var sb := StyleBoxFlat.new()
	sb.bg_color = MAIN_COLOR
	sb.set_corner_radius_all(30)
	sb.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = _title()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_override("font", HUD_FONT)
	_title_label.add_theme_font_size_override("font_size", 32)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_title_label)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	vbox.add_child(tabs)
	_left_tab = _make_tab(_left_text())
	_left_tab.pressed.connect(func() -> void: _set_tab(true))
	tabs.add_child(_left_tab)
	_right_tab = _make_tab(_right_text())
	_right_tab.pressed.connect(func() -> void: _set_tab(false))
	tabs.add_child(_right_tab)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 8)
	scroll.add_child(_content)

	# close X at the panel's top-right corner. Parented to the popup root (NOT
	# the PanelContainer, which would force-lay-it-out over the content) and
	# offset from screen-centre to the panel corner (panel half-size 250x430).
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_override("font", HUD_FONT)
	close_btn.set_anchors_preset(Control.PRESET_CENTER)
	close_btn.offset_left = 208
	close_btn.offset_top = -422
	close_btn.offset_right = 242
	close_btn.offset_bottom = -388
	close_btn.pressed.connect(close)
	add_child(close_btn)


func _make_tab(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HUD_FONT)
	b.add_theme_font_size_override("font_size", 22)
	return b


func open() -> void:
	visible = true
	GameManager.pause()
	_set_tab(_open_on_left())


func close() -> void:
	if not visible:
		return
	visible = false
	GameManager.resume()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _set_tab(left: bool) -> void:
	_showing_left = left
	_left_tab.disabled = left
	_right_tab.disabled = not left
	_refresh()


# Re-run the active tab's populate (called after each buy/sell/store action so
# affordability, counts and "full" states update like the Unity UI).
func _refresh() -> void:
	_clear()
	if _showing_left:
		_populate_left()
	else:
		_populate_right()


func _clear() -> void:
	for child in _content.get_children():
		child.queue_free()


# Build one row: item icon, name label (dark-blue pill), action button.
func _add_row(label_text: String, icon: Texture2D, button_text: String,
		enabled: bool, on_click: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 58
	row.add_theme_constant_override("separation", 8)

	var icon_rect := TextureRect.new()
	icon_rect.custom_minimum_size = Vector2(58, 58)
	icon_rect.texture = icon
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon_rect)

	var name_label := Label.new()
	name_label.text = label_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_override("font", HUD_FONT)
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	var name_sb := StyleBoxFlat.new()
	name_sb.bg_color = ROW_NAME_COLOR
	name_sb.set_corner_radius_all(10)
	name_sb.set_content_margin_all(6)
	name_label.add_theme_stylebox_override("normal", name_sb)
	row.add_child(name_label)

	var button := Button.new()
	button.text = button_text
	button.disabled = not enabled
	button.custom_minimum_size.x = 200
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", HUD_FONT)
	button.add_theme_font_size_override("font_size", 20)
	if enabled and on_click.is_valid():
		button.pressed.connect(on_click)
	row.add_child(button)

	_content.add_child(row)
