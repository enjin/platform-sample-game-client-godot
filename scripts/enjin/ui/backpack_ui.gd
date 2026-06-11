# Blockchain backpack: lists the managed wallet's tokens with melt/transfer
# controls. Control redesign of BackpackUI.cs (UIToolkit). Refresh is
# signal-driven via EnjinManager.wallet_updated; ops are fire-and-forget and
# the server takes 10-20s to finalize, surfaced in the status label.
extends Control

const ROW_SCENE := preload("res://scenes/ui/backpack_item_row.tscn")

@onready var rows: VBoxContainer = %ItemRows
@onready var recipient_edit: LineEdit = %RecipientEdit
@onready var status_label: Label = %StatusLabel
@onready var close_button: Button = %CloseButton


func _ready() -> void:
	visible = false
	EnjinManager.wallet_updated.connect(_refresh)
	EnjinManager.login_complete.connect(func(_ok: bool) -> void: _refresh())
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("open_backpack"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	visible = true
	if not EnjinManager.is_logged_in():
		status_label.text = "Not logged in - blockchain features disabled."
		_clear_rows()
		return
	status_label.text = "Loading wallet..."
	# fire-and-forget; wallet_updated repopulates when the fetch lands
	EnjinManager.get_managed_wallet_tokens()


func close() -> void:
	visible = false


func set_status(text: String) -> void:
	status_label.text = text


func _clear_rows() -> void:
	for child in rows.get_children():
		child.queue_free()


func _refresh() -> void:
	if not visible:
		return  # mirrors BackpackUI.Refresh's hidden no-op
	_clear_rows()
	var account = EnjinManager.wallet_account
	if account == null:
		status_label.text = "No wallet data yet."
		return
	status_label.text = "Wallet: %s" % account.account.address
	for ta in account.token_accounts:
		var row := ROW_SCENE.instantiate()
		rows.add_child(row)
		row.setup(ta, recipient_edit, self)
