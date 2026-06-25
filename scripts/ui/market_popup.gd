# Market popup. Port of UIHandler's market tabs: BUY lists GameManager's market
# stock (seeds) gated by affordability; SELL lists the player's inventory and
# only Products (items with a sell_price) can be sold. Opens on the Sell tab.
extends "res://scripts/ui/shop_popup.gd"


func _title() -> String: return "Market"
func _left_text() -> String: return "Buy"
func _right_text() -> String: return "Sell"
func _open_on_left() -> bool: return false  # Unity opens Sell by default


func _populate_left() -> void:  # Buy
	for item in GameManager.market_entries:
		var afford: bool = GameManager.coins >= item.buy_price
		var text := "Buy 1 for %d" % item.buy_price if afford \
			else "Cannot afford cost of %d" % item.buy_price
		_add_row(item.display_name, item.item_sprite, text, afford,
			func() -> void:
				if GameManager.player:
					GameManager.player.buy_item(item)
				_refresh())


func _populate_right() -> void:  # Sell
	var inventory := GameManager.inventory
	if inventory == null:
		return
	for i in InventorySystem.SIZE:
		var entry = inventory.entries[i]
		var item = entry.item
		if item == null:
			continue
		if "sell_price" in item:
			var count: int = entry.stack_size
			var idx := i
			_add_row(item.display_name, item.item_sprite,
				"Sell %d for %d" % [count, item.sell_price * count], true,
				func() -> void:
					if GameManager.player:
						GameManager.player.sell_item(idx, count)
					_refresh())
		else:
			_add_row(item.display_name, item.item_sprite, "Cannot Sell", false,
				Callable())
