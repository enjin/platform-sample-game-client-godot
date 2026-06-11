# Fixed 9-slot player inventory. Port of InventorySystem.cs; the `changed`
# signal replaces Unity's static UIHandler.UpdateInventory calls.
class_name InventorySystem
extends RefCounted

signal changed

const SIZE := 9


class InventoryEntry:
	var item: Item = null
	var stack_size: int = 0


var entries: Array[InventoryEntry] = []
var equipped_index: int = 0

var equipped_item: Item:
	get:
		return entries[equipped_index].item


func _init() -> void:
	for i in SIZE:
		entries.append(InventoryEntry.new())


# Returns true if the equipped item was used. `user` (the player) anchors the
# use sound, matching Unity's PlaySFXAt(player.position, ...).
func use_equipped(target: Vector2i, user: Node2D = null) -> bool:
	var item := equipped_item
	if item == null or not item.can_use(target):
		return false
	if not item.use(target):
		return false
	if not item.use_sound.is_empty() and user != null \
			and user.has_node("/root/SoundManager"):
		user.get_node("/root/SoundManager").play_sfx_at(
			user.global_position, item.use_sound.pick_random())
	if item.consumable:
		entries[equipped_index].stack_size -= 1
		if entries[equipped_index].stack_size == 0:
			entries[equipped_index].item = null
		changed.emit()
	return true


func can_fit_item(new_item: Item, amount: int) -> bool:
	var to_fit := amount
	for entry in entries:
		if entry.item == new_item:
			to_fit -= new_item.max_stack_size - entry.stack_size
			if to_fit <= 0:
				return true
	for entry in entries:
		if entry.item == null:
			to_fit -= new_item.max_stack_size
			if to_fit <= 0:
				return true
	return to_fit == 0


func get_maximum_amount_fit(item: Item) -> int:
	var can_fit := 0
	for entry in entries:
		if entry.item == null:
			can_fit += item.max_stack_size
		elif entry.item == item:
			can_fit += item.max_stack_size - entry.stack_size
	return can_fit


func get_index_of_item(item: Item, return_only_not_full: bool) -> int:
	for i in SIZE:
		if entries[i].item == item and (not return_only_not_full
				or entries[i].stack_size != item.max_stack_size):
			return i
	return -1


func add_item(new_item: Item, amount: int = 1) -> bool:
	var remaining := amount
	for entry in entries:
		if entry.item == new_item and entry.stack_size < new_item.max_stack_size:
			var fit: int = mini(new_item.max_stack_size - entry.stack_size, remaining)
			entry.stack_size += fit
			remaining -= fit
			if remaining == 0:
				changed.emit()
				return true
	for entry in entries:
		if entry.item == null:
			entry.item = new_item
			var fit: int = mini(new_item.max_stack_size, remaining)
			entry.stack_size = fit
			remaining -= fit
			if remaining == 0:
				changed.emit()
				return true
	changed.emit()
	return remaining == 0


# Returns the amount actually removed.
func remove(index: int, count: int) -> int:
	if index < 0 or index >= SIZE:
		return 0
	var amount: int = mini(count, entries[index].stack_size)
	entries[index].stack_size -= amount
	if entries[index].stack_size == 0:
		entries[index].item = null
	changed.emit()
	return amount


func equip_next() -> void:
	equipped_index = (equipped_index + 1) % SIZE
	changed.emit()


func equip_prev() -> void:
	equipped_index = (equipped_index + SIZE - 1) % SIZE
	changed.emit()


func equip_item(index: int) -> void:
	if index < 0 or index >= SIZE:
		return
	equipped_index = index
	changed.emit()


# Save format mirrors Unity's InventorySaveData list (null = empty slot).
func save_data() -> Array:
	var data := []
	for entry in entries:
		if entry.item != null:
			data.append({"item_id": entry.item.unique_id, "amount": entry.stack_size})
		else:
			data.append(null)
	return data


func load_data(data: Array, item_database) -> void:
	for i in mini(data.size(), SIZE):
		if data[i] != null:
			entries[i].item = item_database.get_from_id(data[i]["item_id"])
			entries[i].stack_size = int(data[i]["amount"])
		else:
			entries[i].item = null
			entries[i].stack_size = 0
	changed.emit()
