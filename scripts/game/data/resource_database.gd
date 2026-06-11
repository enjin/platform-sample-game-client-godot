# In-memory unique_id -> Resource lookup, built by scanning resource folders.
# Replaces Unity's BaseDatabase<T> ScriptableObjects (ItemDatabase,
# CropDatabase). DirAccess works over res:// in exported builds too because
# .tres files are listed in the PCK index.
class_name ResourceDatabase
extends RefCounted

var _by_id := {}


func _init(scan_dirs: Array[String]) -> void:
	for dir_path in scan_dirs:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for file in dir.get_files():
			# exported builds list imported resources as .tres.remap
			file = file.trim_suffix(".remap")
			if not file.ends_with(".tres"):
				continue
			var res: Resource = load(dir_path + "/" + file)
			if res != null and "unique_id" in res:
				_by_id[res.unique_id] = res


func get_from_id(id: String) -> Resource:
	return _by_id.get(id)


func size() -> int:
	return _by_id.size()
