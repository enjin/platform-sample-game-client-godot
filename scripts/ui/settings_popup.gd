# Settings popup. Port of SettingMenu.cs: a centered blue panel with a
# resolution dropdown, fullscreen toggle, three volume sliders (Master/Music/
# SFX -> the Master/BGM/SFX audio buses), an Enjin login/logout control, and a
# quit button. Opened from the HUD's "Menu" button; pauses while open.
extends Control

const HUD_FONT := preload("res://fonts/cursecasual/curse_casual.ttf")
const MAIN_COLOR := Color(0, 0.498, 0.886)

# A handful of common 16:9 windowed resolutions, plus the native one.
const RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440),
]

var _res_dropdown: OptionButton
var _fullscreen: CheckButton
var _login_box: VBoxContainer
var _email: LineEdit
var _password: LineEdit
var _login_button: Button
var _logout_button: Button


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	EnjinManager.login_complete.connect(func(_ok: bool) -> void: _refresh_login())
	EnjinManager.logout_complete.connect(func(_ok: bool) -> void: _refresh_login())


func _build() -> void:
	# dim backdrop (Unity uses rgba(0,0,0,0.3)); clicking it closes the menu
	var dim := Button.new()
	dim.flat = true
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.focus_mode = Control.FOCUS_NONE
	var dim_sb := StyleBoxFlat.new()
	dim_sb.bg_color = Color(0, 0, 0, 0.3)
	dim.add_theme_stylebox_override("normal", dim_sb)
	dim.add_theme_stylebox_override("hover", dim_sb)
	dim.add_theme_stylebox_override("pressed", dim_sb)
	dim.pressed.connect(close)
	add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(560, 480)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = -240
	panel.offset_bottom = 240
	var sb := StyleBoxFlat.new()
	sb.bg_color = MAIN_COLOR
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := _label("Settings", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# resolution
	_res_dropdown = OptionButton.new()
	_res_dropdown.add_theme_font_override("font", HUD_FONT)
	for res in RESOLUTIONS:
		_res_dropdown.add_item("%d x %d" % [res.x, res.y])
	_res_dropdown.item_selected.connect(_on_resolution_selected)
	vbox.add_child(_row("Resolution", _res_dropdown))

	# fullscreen
	_fullscreen = CheckButton.new()
	_fullscreen.button_pressed = DisplayServer.window_get_mode() == \
		DisplayServer.WINDOW_MODE_FULLSCREEN
	_fullscreen.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(_row("Fullscreen", _fullscreen))

	vbox.add_child(_separator())

	# volume sliders -> audio buses
	vbox.add_child(_row("Main Volume", _make_volume_slider("Master")))
	vbox.add_child(_row("Music Volume", _make_volume_slider("BGM")))
	vbox.add_child(_row("SFX Volume", _make_volume_slider("SFX")))

	vbox.add_child(_separator())

	# login / logout (Enjin)
	_login_box = VBoxContainer.new()
	_login_box.add_theme_constant_override("separation", 6)
	vbox.add_child(_login_box)

	_email = LineEdit.new()
	_email.placeholder_text = "Email"
	_login_box.add_child(_email)
	_password = LineEdit.new()
	_password.placeholder_text = "Password"
	_password.secret = true
	_login_box.add_child(_password)
	_login_button = _button("Login")
	_login_button.pressed.connect(_on_login_pressed)
	_login_box.add_child(_login_button)

	_logout_button = _button("Logout")
	_logout_button.pressed.connect(func() -> void: EnjinManager.logout())
	vbox.add_child(_logout_button)

	vbox.add_child(_separator())

	var quit := _button("Quit Game")
	quit.pressed.connect(func() -> void: get_tree().quit())
	vbox.add_child(quit)

	# close X at the panel's top-right corner. Parented to the popup root (NOT
	# the PanelContainer) and offset from centre (panel half-size 280x240).
	var close_btn := _button("X")
	close_btn.set_anchors_preset(Control.PRESET_CENTER)
	close_btn.offset_left = 236
	close_btn.offset_top = -232
	close_btn.offset_right = 272
	close_btn.offset_bottom = -196
	close_btn.pressed.connect(close)
	add_child(close_btn)


# ---- open / close ----

func open() -> void:
	visible = true
	GameManager.pause()
	_sync_resolution_selection()
	_refresh_login()


func close() -> void:
	if not visible:
		return
	visible = false
	GameManager.resume()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# ---- handlers ----

func _on_resolution_selected(index: int) -> void:
	if _fullscreen.button_pressed:
		return
	DisplayServer.window_set_size(RESOLUTIONS[index])


func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on
		else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_login_pressed() -> void:
	if _email.text.is_empty() or _password.text.is_empty():
		return
	_login_button.disabled = true
	_login_button.text = "Logging in..."
	EnjinManager.register_and_login(_email.text, _password.text)


func _refresh_login() -> void:
	var logged_in := EnjinManager.is_logged_in()
	_login_box.visible = not logged_in
	_logout_button.visible = logged_in
	_login_button.disabled = false
	_login_button.text = "Login"


func _sync_resolution_selection() -> void:
	var size := DisplayServer.window_get_size()
	for i in RESOLUTIONS.size():
		if RESOLUTIONS[i] == size:
			_res_dropdown.select(i)
			return


# ---- widget helpers ----

func _make_volume_slider(bus: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.01
	s.custom_minimum_size.x = 280
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value = SoundManager.get_volume(bus)
	s.value_changed.connect(func(v: float) -> void: SoundManager.set_volume(bus, v))
	return s


func _label(text: String, size: int = 20) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", HUD_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color.WHITE)
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", HUD_FONT)
	b.add_theme_font_size_override("font_size", 20)
	return b


# A label + control on one row.
func _row(label_text: String, control: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	var l := _label(label_text)
	l.custom_minimum_size.x = 150
	h.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(control)
	return h


func _separator() -> Control:
	var line := ColorRect.new()
	line.color = Color.WHITE
	line.custom_minimum_size.y = 3
	return line
