# A clickable world object that opens a HUD popup, the way Unity's MarketStall
# and Warehouse (both InteractiveObject) call UIHandler.OpenMarket/Warehouse.
# Lives on an Area2D whose collision_layer includes the interactive layer
# (bit 2 / value 4); player_controller.gd point-queries that mask and calls
# interacted_with() when the player clicks while hovering it.
extends Area2D

@export_enum("market", "warehouse") var kind: String = "market"


func interacted_with() -> void:
	match kind:
		"market":
			GameManager.open_market()
		"warehouse":
			GameManager.open_warehouse()
