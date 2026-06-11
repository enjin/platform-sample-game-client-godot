# Main menu. Port of MainMenuHandler.cs plus the login form: register-or-login
# creates a managed wallet server-side and stores the JWT. Start works without
# logging in - blockchain features simply no-op until authenticated, same as
# the Unity build.
extends Control

const FARM_SCENE := "res://scenes/farm_outdoor.tscn"

@onready var start_button: Button = %StartButton
@onready var quit_button: Button = %QuitButton
@onready var email_edit: LineEdit = %EmailEdit
@onready var password_edit: LineEdit = %PasswordEdit
@onready var login_button: Button = %LoginButton
@onready var login_status: Label = %LoginStatus


func _ready() -> void:
	start_button.pressed.connect(_on_start)
	quit_button.pressed.connect(func() -> void: get_tree().quit())
	login_button.pressed.connect(_on_login)
	EnjinManager.login_complete.connect(_on_login_complete)
	if EnjinManager.is_logged_in():
		login_status.text = "Logged in (saved session)."
		_set_login_form_visible(false)
	start_button.grab_focus()


func _on_start() -> void:
	start_button.disabled = true
	GameManager.move_to(FARM_SCENE, 0)


func _on_login() -> void:
	var email := email_edit.text.strip_edges()
	var password := password_edit.text
	if email.is_empty() or password.is_empty():
		login_status.text = "Enter email and password."
		return
	login_button.disabled = true
	login_status.text = "Logging in..."
	EnjinManager.register_and_login(email, password)


func _on_login_complete(success: bool) -> void:
	login_button.disabled = false
	if success:
		login_status.text = "Logged in - tokens enabled."
		_set_login_form_visible(false)
	else:
		login_status.text = "Login failed - is the game server running?"


func _set_login_form_visible(form_visible: bool) -> void:
	email_edit.visible = form_visible
	password_edit.visible = form_visible
	login_button.visible = form_visible
