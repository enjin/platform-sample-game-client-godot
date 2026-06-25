# Warehouse popup. Port of WarehouseUI: STORE moves a whole player stack into
# GameManager.storage; RETRIEVE pulls a stored stack back into the inventory,
# capped by what currently fits. Opens on the Store tab.
extends "res://scripts/ui/shop_popup.gd"


func _title() -> String: return "Warehouse"
func _left_text() -> String: return "Store"
func _right_text() -> String: return "Retrieve"
func _open_on_left() -> bool: return true


func _populate_left() -> void:  # Store
	var inventory := GameManager.inventory
	if inventory == null:
		return
	for i in InventorySystem.SIZE:
		var entry = inventory.entries[i]
		var item = entry.item
		if item == null:
			continue
		var idx := i
		var amount: int = entry.stack_size
		_add_row("%s (x%d)" % [item.display_name, amount], item.item_sprite,
			"Store", true,
			func() -> void:
				GameManager.storage.store(item, amount)
				inventory.remove(idx, amount)
				_refresh())


func _populate_right() -> void:  # Retrieve
	var inventory := GameManager.inventory
	var storage := GameManager.storage
	if inventory == null or storage == null:
		return
	for i in storage.content.size():
		var entry = storage.content[i]
		if entry.stack_size == 0:
			continue
		var item: Item = entry.item
		var idx := i
		var fits: int = inventory.get_maximum_amount_fit(item)
		var can_take := fits > 0
		_add_row("%s (x%d)" % [item.display_name, entry.stack_size],
			item.item_sprite,
			"Retrieve" if can_take else "Inventory Full", can_take,
			func() -> void:
				var amount: int = mini(entry.stack_size,
					inventory.get_maximum_amount_fit(item))
				if amount > 0:
					storage.retrieve(idx, amount)
					inventory.add_item(item, amount)
				_refresh())
