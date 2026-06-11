# Phase 1 verification harness.
#
# Wires up buttons + a log panel to exercise every EnjinApiService / EnjinManager
# entry point against a running C# game server. This is the Godot equivalent of
# the Unity EnjinSdkSmoke / GameServerSmoke flow at the API level -- a fuller
# port of GameServerSmoke (with the same scene/look) lands in Phase 7.
#
# How to run:
#   1. Start the game server (see ../platform-sample-game-server README).
#   2. In Godot, open this project and play `scenes/debug_enjin.tscn`.
#   3. The console + the in-scene log panel will report each call's outcome.

extends Control

@onready var _log: TextEdit = $Root/Log
@onready var _email: LineEdit = $Root/Auth/Email
@onready var _password: LineEdit = $Root/Auth/Password
@onready var _token_id: LineEdit = $Root/TokenRow/TokenId
@onready var _amount: SpinBox = $Root/TokenRow/Amount
@onready var _recipient: LineEdit = $Root/TransferRow/Recipient
@onready var _host: LineEdit = $Root/HostRow/Host


func _ready() -> void:
	_host.text = EnjinApiService.host
	EnjinManager.login_complete.connect(_on_login_complete)
	EnjinManager.logout_complete.connect(_on_logout_complete)
	EnjinManager.wallet_updated.connect(_on_wallet_updated)

	$Root/HostRow/ApplyHost.pressed.connect(_apply_host)
	$Root/ButtonGrid/HealthCheck.pressed.connect(_on_health_check)
	$Root/ButtonGrid/Login.pressed.connect(_on_login)
	$Root/ButtonGrid/Logout.pressed.connect(EnjinManager.logout)
	$Root/ButtonGrid/Wallet.pressed.connect(EnjinManager.get_managed_wallet_tokens)
	$Root/ButtonGrid/Mint.pressed.connect(_on_mint)
	$Root/ButtonGrid/Melt.pressed.connect(_on_melt)
	$Root/ButtonGrid/Transfer.pressed.connect(_on_transfer)

	_log_line("Ready. Host = %s. Logged in: %s" % [EnjinApiService.host, EnjinManager.is_logged_in()])


func _apply_host() -> void:
	EnjinApiService.host = _host.text.strip_edges()
	_log_line("Host set to %s" % EnjinApiService.host)


func _on_health_check() -> void:
	_log_line("Health check...")
	var ok := await EnjinApiService.perform_health_check()
	_log_line("Health check: %s" % ("OK" if ok else "FAIL"))


func _on_login() -> void:
	var email := _email.text.strip_edges()
	var pw := _password.text
	if email.is_empty() or pw.is_empty():
		_log_line("Login: email and password required.")
		return
	await EnjinManager.register_and_login(email, pw)


func _on_login_complete(success: bool) -> void:
	_log_line("Login complete: success=%s" % success)


func _on_logout_complete(_success: bool) -> void:
	_log_line("Logout complete.")


func _on_wallet_updated() -> void:
	var w := EnjinManager.wallet_account
	if w == null:
		_log_line("Wallet updated: <null>")
		return
	var addr: String = "?" if w.account == null else w.account.address
	_log_line("Wallet updated. Address=%s. Tokens=%d:" % [addr, w.token_accounts.size()])
	for ta in w.token_accounts:
		var cid: String = "?" if ta.token == null or ta.token.collection == null else ta.token.collection.collection_id
		var tid: String = "?" if ta.token == null else ta.token.token_id
		_log_line("  - balance=%s collection=%s tokenId=%s" % [ta.balance, cid, tid])


func _on_mint() -> void:
	var tid := _token_id.text.strip_edges()
	if tid.is_empty():
		_log_line("Mint: tokenId required.")
		return
	await EnjinManager.mint_token(tid, int(_amount.value))


func _on_melt() -> void:
	var tid := _token_id.text.strip_edges()
	if tid.is_empty():
		_log_line("Melt: tokenId required.")
		return
	await EnjinManager.melt_token(tid, int(_amount.value))


func _on_transfer() -> void:
	var tid := _token_id.text.strip_edges()
	var rcpt := _recipient.text.strip_edges()
	if tid.is_empty() or rcpt.is_empty():
		_log_line("Transfer: tokenId and recipient required.")
		return
	await EnjinManager.transfer_token(tid, int(_amount.value), rcpt)


func _log_line(msg: String) -> void:
	var ts := Time.get_time_string_from_system()
	_log.text += "[%s] %s\n" % [ts, msg]
	# Scroll to bottom.
	_log.scroll_vertical = _log.get_line_count()
