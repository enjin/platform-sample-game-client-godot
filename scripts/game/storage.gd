# Warehouse storage. Port of Storage.cs: a separate item store (not the player
# inventory) the Warehouse UI moves stacks into and out of. Local only - Unity
# marked the blockchain hooks "TODO" and never wired them.
class_name Storage
extends RefCounted


class StorageEntry:
	var item: Item = null
	var stack_size: int = 0


var content: Array[StorageEntry] = []


# Add a whole stack; merges into an existing entry for the same item.
func store(item: Item, amount: int) -> void:
	for entry in content:
		if entry.item == item:
			entry.stack_size += amount
			return
	var entry := StorageEntry.new()
	entry.item = item
	entry.stack_size = amount
	content.append(entry)


# Pull up to `amount` out of a stack; returns how much was actually removed.
# Empty stacks are kept in the list (Unity does the same) - the UI hides them.
func retrieve(index: int, amount: int) -> int:
	if index < 0 or index >= content.size():
		return 0
	var actual: int = mini(amount, content[index].stack_size)
	content[index].stack_size -= actual
	return actual
