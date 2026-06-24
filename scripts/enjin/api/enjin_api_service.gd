# Port of HappyHarvest.EnjinIntegration.API.EnjinApiService
# (Assets/Enjin Integration/Scripts/API/EnjinApiService.cs).
#
# Thin REST client over the C# game server (../platform-sample-game-server).
# Endpoints exercised:
#   GET  /api/auth/health-check
#   POST /api/auth/register
#   POST /api/token/mint            (bearer auth)
#   POST /api/token/melt            (bearer auth)
#   POST /api/token/transfer        (bearer auth)
#   GET  /api/wallet/get-tokens     (bearer auth)
#
# The Unity version used UnityWebRequest + async/await Task<T>. Godot's
# HTTPRequest is a Node that completes via the `request_completed` signal and
# is intentionally single-shot (one in-flight request per node). We spawn a
# dedicated child HTTPRequest per call so callers can run requests in parallel
# without serialising them.
#
# Autoloaded as `EnjinApiService` (see project.godot).

extends Node

# Default host matches the C# game server's default. Override at runtime if you
# point the client at a different deployment (e.g. EnjinApiService.host = ...).
var host: String = "http://localhost:3000"


func _ready() -> void:
	# Mirrors EnjinApiService.Start(): prove the server is reachable on boot.
	# Result is logged but ignored; failures here are non-fatal because the
	# user can fix the host and retry from the menu.
	var ok := await perform_health_check()
	if ok:
		print("[EnjinApiService] Health check OK against %s" % host)
	else:
		push_warning("[EnjinApiService] Health check failed against %s" % host)


# -------------------------- Public API --------------------------

func perform_health_check() -> bool:
	var result := await _send(host + "/api/auth/health-check", HTTPClient.METHOD_GET)
	if not result.ok:
		push_error("Health check failed: %s" % result.error)
		return false
	var parsed: Variant = _parse_json(result.body)
	if parsed is Dictionary and parsed.get("status", "") == "OK":
		return true
	push_error("Server connection failed or returned an unexpected response: %s" % result.body)
	return false


# Returns the bearer token on success, or empty string on failure. Matches the
# Unity LoginUser(string,string) -> string contract. The server endpoint is
# /api/auth/register, which both registers and returns a session token; if the
# account already exists the server responds with the same token shape.
func login_user(email: String, password: String) -> String:
	var body := {"email": email, "password": password}
	var result := await _send(host + "/api/auth/register", HTTPClient.METHOD_POST, body)
	if not result.ok:
		push_error("Login failed: %s" % result.error)
		return ""
	var parsed: Variant = _parse_json(result.body)
	if parsed is Dictionary:
		var token: String = str(parsed.get("token", ""))
		if not token.is_empty():
			print("[EnjinApiService] Login successful. Token received.")
			return token
	push_error("Login returned no token: %s" % result.body)
	return ""


func mint_token(user_auth: String, token_id: String, amount: int) -> bool:
	return await _bool_token_op(user_auth, "mint", {"tokenId": token_id, "amount": str(amount)})


func melt_token(user_auth: String, token_id: String, amount: int) -> bool:
	return await _bool_token_op(user_auth, "melt", {"tokenId": token_id, "amount": str(amount)})


func transfer_token(user_auth: String, token_id: String, amount: int, recipient: String) -> bool:
	return await _bool_token_op(user_auth, "transfer", {
		"tokenId": token_id,
		"amount": str(amount),
		"recipient": recipient,
	})


# Returns a PlatformModels.ManagedWalletAccount or null. A 401 here triggers
# an EnjinManager.logout() so stale tokens don't keep failing silently.
func get_managed_wallet_tokens(user_auth: String) -> PlatformModels.ManagedWalletAccount:
	var result := await _send(
		host + "/api/wallet/get-tokens",
		HTTPClient.METHOD_GET,
		null,
		_auth_headers(user_auth),
	)
	if result.status_code == 401:
		push_warning("Authorization failed (401). Forcing logout.")
		# EnjinManager is an autoload, not an Engine singleton, so
		# Engine.has_singleton() is always false here. Resolve it through the
		# scene tree instead; get_node_or_null keeps this safe when the API
		# service is exercised outside the normal app (e.g. test harnesses).
		var manager := get_node_or_null(^"/root/EnjinManager")
		if manager != null and manager.has_method("logout"):
			manager.logout()
		return null
	if not result.ok:
		push_error("GetManagedWalletTokens failed: %s" % result.error)
		return null
	var parsed: Variant = _parse_json(result.body)
	if parsed is Dictionary:
		var wallet := PlatformModels.ManagedWalletAccount.from_dict(parsed)
		if wallet != null and wallet.account != null:
			print("[EnjinApiService] Managed wallet address: %s" % wallet.account.address)
		return wallet
	push_error("GetManagedWalletTokens: unexpected response: %s" % result.body)
	return null


# -------------------------- Internals --------------------------

# Compact result struct so callers don't need to juggle HTTPRequest's 4-arg
# signal payload. `ok` means we got a 2xx; non-2xx returns ok=false with the
# response body still available in `body` for diagnostics.
class _Response:
	var ok: bool = false
	var status_code: int = 0
	var body: String = ""
	var error: String = ""


func _bool_token_op(user_auth: String, op: String, body: Dictionary) -> bool:
	var url := "%s/api/token/%s" % [host, op]
	var token_id: String = str(body.get("tokenId", "?"))
	var result := await _send(url, HTTPClient.METHOD_POST, body, _auth_headers(user_auth))
	if not result.ok:
		push_error("%s of #%s failed: %s" % [op, token_id, result.error])
		return false
	var parsed: Variant = _parse_json(result.body)
	if parsed is Dictionary and bool(parsed.get("success", false)):
		print("[EnjinApiService] Successfully %sed token #%s" % [op, token_id])
		return true
	push_error("%s of #%s did not report success: %s" % [op, token_id, result.body])
	return false


func _auth_headers(user_auth: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"authorization: bearer " + user_auth,
	])


# Core HTTP helper. Spawns a one-shot HTTPRequest child so concurrent callers
# don't trip over HTTPRequest's single-request-at-a-time restriction.
func _send(
	url: String,
	method: int,
	body: Variant = null,
	headers: PackedStringArray = PackedStringArray(["Content-Type: application/json"]),
) -> _Response:
	var req := HTTPRequest.new()
	add_child(req)

	var body_str := ""
	if body != null:
		body_str = JSON.stringify(body)

	var result := _Response.new()
	var err := req.request(url, headers, method, body_str)
	if err != OK:
		result.error = "HTTPRequest.request() returned error %s" % err
		req.queue_free()
		return result

	var signal_args: Array = await req.request_completed
	# request_completed(result, response_code, headers, body)
	var http_result: int = signal_args[0]
	result.status_code = int(signal_args[1])
	result.body = (signal_args[3] as PackedByteArray).get_string_from_utf8()
	req.queue_free()

	if http_result != HTTPRequest.RESULT_SUCCESS:
		result.error = "HTTP transport error: result=%s status=%s" % [http_result, result.status_code]
		return result
	if result.status_code < 200 or result.status_code >= 300:
		result.error = "HTTP %s: %s" % [result.status_code, result.body]
		return result
	result.ok = true
	return result


func _parse_json(text: String) -> Variant:
	if text.is_empty():
		return null
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		push_error("JSON parse failed at line %s: %s" % [json.get_error_line(), json.get_error_message()])
		return null
	return json.data
