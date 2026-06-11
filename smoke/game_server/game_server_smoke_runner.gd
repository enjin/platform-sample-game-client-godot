# Drives the real REST layer (EnjinApiService autoload) through the full
# sample-server flow, exactly like Unity's GameServerSmokeRunner:
#   health-check -> register/login -> get-tokens (baseline)
#   -> mint -> get-tokens -> melt -> get-tokens -> transfer -> get-tokens
# Wire-format sanity check before clicking through the game UI.
#
# Headless / CI:
#   SMOKE_EMAIL=a@b.c SMOKE_PASSWORD=secret \
#   godot --headless --path . smoke/game_server/game_server_smoke.tscn \
#         -- --quit-after-smoke ; echo $?
extends Control

@export var config: GameServerSmokeConfig

var _running := false
var _steps_passed := 0
var _steps_total := 0
var _quit_after := false

@onready var log_label: RichTextLabel = %Log
@onready var run_button: Button = %RunButton


func _ready() -> void:
	run_button.pressed.connect(run_smoke)
	if config == null:
		config = GameServerSmokeConfig.new()
	# env fallbacks keep credentials out of committed files
	if OS.get_environment("SMOKE_HOST") != "":
		config.server_host = OS.get_environment("SMOKE_HOST")
	if OS.get_environment("SMOKE_EMAIL") != "":
		config.email = OS.get_environment("SMOKE_EMAIL")
	if OS.get_environment("SMOKE_PASSWORD") != "":
		config.password = OS.get_environment("SMOKE_PASSWORD")
	_quit_after = "--quit-after-smoke" in OS.get_cmdline_user_args()
	if config.run_on_start:
		run_smoke()


func run_smoke() -> void:
	if _running:
		_log("(smoke already running; ignoring re-entry)")
		return
	_running = true
	await _run_smoke()
	_running = false
	if _quit_after:
		get_tree().quit(0 if _steps_passed == _steps_total else 1)


func _run_smoke() -> void:
	log_label.clear()
	_steps_passed = 0
	_steps_total = 9
	EnjinApiService.host = config.server_host

	_log("=== Game server REST smoke test (Godot client -> C# backend) ===")
	_log("Server: %s" % config.server_host)
	_log("Email:  %s" % config.email)
	_log("Mint:   token=%s amount=%d" % [config.mint_token_id, config.mint_amount])
	_log("Melt:   token=%s amount=%d" % [config.mint_token_id, config.melt_amount])
	_log("Xfer:   token=%s amount=%d -> %s" % [config.transfer_token_id,
		config.transfer_amount, config.transfer_recipient])
	_log("Godot:  %s" % Engine.get_version_info().string)
	_log("")

	if config.email.is_empty() or config.password.is_empty():
		_log("ERROR: email and password must be set (config resource or SMOKE_EMAIL/SMOKE_PASSWORD).")
		return

	# ---- 1. health check ----
	_log("--- 1. health check ---")
	var healthy: bool = await EnjinApiService.perform_health_check()
	if not healthy:
		_log("ABORT: server health check failed. Is the sample server running on %s?"
			% config.server_host)
		return
	_pass("healthy=true")

	# ---- 2. register / login ----
	_log("--- 2. register (doubles as login) ---")
	var jwt: String = await EnjinApiService.login_user(config.email, config.password)
	if jwt.is_empty():
		_log("ABORT: login returned no token. Check server logs.")
		return
	_pass("token=" + _mask(jwt))

	# ---- 3. baseline wallet ----
	if not await _dump_wallet(jwt, "3. get-tokens (baseline)"):
		return

	# ---- 4. mint ----
	_log("--- 4. mint %d of token #%s ---" % [config.mint_amount, config.mint_token_id])
	var minted: bool = await EnjinApiService.mint_token(jwt, config.mint_token_id,
		config.mint_amount)
	if not minted:
		_log("ABORT: mint failed.")
		return
	_pass("minted")
	await _pause()
	if not await _dump_wallet(jwt, "5. get-tokens (post-mint)"):
		return

	# ---- 6. melt ----
	_log("--- 6. melt %d of token #%s ---" % [config.melt_amount, config.mint_token_id])
	var melted: bool = await EnjinApiService.melt_token(jwt, config.mint_token_id,
		config.melt_amount)
	if not melted:
		_log("ABORT: melt failed.")
		return
	_pass("melted")
	await _pause()
	if not await _dump_wallet(jwt, "7. get-tokens (post-melt)"):
		return

	# ---- 8. transfer ----
	_log("--- 8. transfer %d of token #%s -> %s ---" % [config.transfer_amount,
		config.transfer_token_id, config.transfer_recipient])
	var transferred: bool = await EnjinApiService.transfer_token(jwt,
		config.transfer_token_id, config.transfer_amount, config.transfer_recipient)
	if not transferred:
		_log("ABORT: transfer failed.")
		return
	_pass("transferred")
	await _pause()
	if not await _dump_wallet(jwt, "9. get-tokens (post-transfer)"):
		return

	_log("=== Done. %d/%d steps passed. ===" % [_steps_passed, _steps_total])


func _dump_wallet(jwt: String, label: String) -> bool:
	_log("--- %s ---" % label)
	var wallet = await EnjinApiService.get_managed_wallet_tokens(jwt)
	if wallet == null:
		# fresh accounts 404 here until the managed wallet finishes
		# provisioning on-chain; Unity's DumpWallet logs and continues too
		_log("  (null wallet returned - may still be provisioning)")
		_log("")
		_steps_passed += 1
		return true
	_log("  address: %s" % (wallet.account.address if wallet.account else "?"))
	if wallet.token_accounts.is_empty():
		_log("  tokenAccounts: (empty)")
	else:
		for ta in wallet.token_accounts:
			_log("  - tokenId=%s balance=%s collection=%s" % [
				ta.token.token_id if ta.token else "?",
				ta.balance,
				ta.token.collection.collection_id if ta.token and ta.token.collection else "?"])
	_log("")
	_steps_passed += 1
	return true


func _pause() -> void:
	await get_tree().create_timer(config.pause_between_steps_seconds).timeout


func _pass(message: String) -> void:
	_steps_passed += 1
	_log("  OK: " + message)
	_log("")


func _mask(token: String) -> String:
	if token.length() <= 10:
		return "***"
	return token.substr(0, 6) + "..." + token.substr(token.length() - 4)


func _log(line: String) -> void:
	log_label.append_text(line + "\n")
	print("[smoke] " + line)
