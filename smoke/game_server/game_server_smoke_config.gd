# Configuration for the game-server smoke scene. Port of
# GameServerSmokeConfig.cs. The populated smoke_config.tres is gitignored
# (it holds a password); copy smoke_config.example.tres and fill it in, or
# use the SMOKE_EMAIL / SMOKE_PASSWORD / SMOKE_HOST environment variables.
class_name GameServerSmokeConfig
extends Resource

@export var server_host: String = "http://localhost:3000"
@export var email: String = ""
@export var password: String = ""
@export var mint_token_id: String = "1"
@export var transfer_token_id: String = "1"
@export var mint_amount: int = 5
@export var melt_amount: int = 2
@export var transfer_amount: int = 1
@export var transfer_recipient: String = "cxNE5bEPcdpfbsMfdLka11Jj1QH7gihFcc9uKqXKtepcQhkPS"
@export var run_on_start: bool = true
@export var pause_between_steps_seconds: float = 1.0
