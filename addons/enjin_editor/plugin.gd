# Godot port of HappyHarvest.EnjinIntegration.EditorTools.StampCollectionIdMenu
# (Assets/Enjin Integration/Editor/StampCollectionIdMenu.cs).
#
# Editor-time helper. Calls the sample game server's
#   GET /api/setup/collection-id
# endpoint and writes the returned id onto every EnjinItem .tres resource
# in the project (so the runtime EnjinManager can match wallet tokens
# against in-game items).
#
# Adds the action under: Project -> Tools -> Stamp Collection ID onto EnjinItem Assets.
#
# Per-machine setup: the most-recently-used host is persisted via
# EditorSettings under `enjin/setup/server_host`.

@tool
extends EditorPlugin

const HOST_SETTING := "enjin/setup/server_host"
const DEFAULT_HOST := "http://localhost:3000"
const MENU_LABEL := "Stamp Collection ID onto EnjinItem Assets"

var _dialog: AcceptDialog = null


func _enter_tree() -> void:
    add_tool_menu_item(MENU_LABEL, _run)


func _exit_tree() -> void:
    remove_tool_menu_item(MENU_LABEL)
    if _dialog != null and is_instance_valid(_dialog):
        _dialog.queue_free()
        _dialog = null


func _run() -> void:
    var es := EditorInterface.get_editor_settings()
    var host: String = es.get_setting(HOST_SETTING) if es.has_setting(HOST_SETTING) else DEFAULT_HOST
    if host == null or str(host).is_empty():
        host = DEFAULT_HOST
    _prompt_for_host(host)


# --- Host prompt -------------------------------------------------------------

func _prompt_for_host(default_value: String) -> void:
    var dlg := ConfirmationDialog.new()
    dlg.title = "Stamp Collection ID"
    dlg.min_size = Vector2i(520, 200)

    var vbox := VBoxContainer.new()
    var lbl := Label.new()
    lbl.text = "Game server base URL (e.g. http://localhost:3000).\n" \
        + "The editor will call <host>/api/setup/collection-id and write the\n" \
        + "value onto every EnjinItem .tres asset in the project."
    lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    vbox.add_child(lbl)

    var host_field := LineEdit.new()
    host_field.text = default_value
    host_field.custom_minimum_size = Vector2(480, 0)
    vbox.add_child(host_field)
    dlg.add_child(vbox)

    dlg.confirmed.connect(func() -> void:
        var host_value := host_field.text.strip_edges().rstrip("/")
        if host_value.is_empty():
            print("[StampCollectionId] Cancelled.")
            return
        var es := EditorInterface.get_editor_settings()
        es.set_setting(HOST_SETTING, host_value)
        _fetch_and_stamp(host_value)
    )
    dlg.canceled.connect(func() -> void: print("[StampCollectionId] Cancelled."))

    EditorInterface.get_base_control().add_child(dlg)
    dlg.popup_centered()


# --- Server fetch + stamp ----------------------------------------------------

func _fetch_and_stamp(host: String) -> void:
    var req := HTTPRequest.new()
    EditorInterface.get_base_control().add_child(req)
    req.timeout = 10.0
    var url := host + "/api/setup/collection-id"
    var err := req.request(url, PackedStringArray(["Accept: application/json"]))
    if err != OK:
        req.queue_free()
        _show("Stamp Collection ID",
            "Failed to start HTTP request to %s (error %s)." % [url, err])
        return

    var signal_args: Array = await req.request_completed
    var http_result: int = signal_args[0]
    var status_code: int = int(signal_args[1])
    var body_bytes: PackedByteArray = signal_args[3]
    req.queue_free()

    var body := body_bytes.get_string_from_utf8()
    if http_result != HTTPRequest.RESULT_SUCCESS:
        _show("Stamp Collection ID",
            "Failed to fetch collection id from %s\n\nHTTP transport error %s." % [url, http_result] \
            + "\nMake sure the server is running and has finished bootstrap.")
        return
    if status_code < 200 or status_code >= 300:
        _show("Stamp Collection ID",
            "Failed to fetch collection id from %s\n\nHTTP %s: %s" % [url, status_code, body])
        return

    var json := JSON.new()
    var parse_err := json.parse(body)
    if parse_err != OK or not (json.data is Dictionary):
        _show("Stamp Collection ID",
            "Failed to parse server response from %s\n\n%s" % [url, body])
        return
    var collection_id := str((json.data as Dictionary).get("collectionId", ""))
    if collection_id.is_empty():
        _show("Stamp Collection ID", "Server returned an empty collection id.")
        return

    var stamped := _stamp_all_enjin_items(collection_id)
    var summary: String
    if stamped.is_empty():
        summary = "No EnjinItem assets found in the project. Nothing to stamp."
    else:
        summary = "Stamped collection id %s onto %d EnjinItem asset(s):\n\n  %s" \
            % [collection_id, stamped.size(), "\n  ".join(stamped)]
    print("[StampCollectionId] " + summary.replace("\n\n", " "))
    _show("Stamp Collection ID", summary)
    EditorInterface.get_resource_filesystem().scan()


# Walks the project for EnjinItem .tres resources and writes `collection_id`
# into each, returning the list of file names touched.
func _stamp_all_enjin_items(collection_id: String) -> Array[String]:
    var touched: Array[String] = []
    var fs := EditorInterface.get_resource_filesystem().get_filesystem()
    _walk_fs(fs, collection_id, touched)
    return touched


func _walk_fs(dir: EditorFileSystemDirectory, collection_id: String, touched: Array[String]) -> void:
    if dir == null:
        return
    for i in dir.get_file_count():
        var path := dir.get_file_path(i)
        # Cheap filter: only consider .tres files; load and type-check
        # before touching to avoid materialising unrelated resources.
        if not path.ends_with(".tres"):
            continue
        var res: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REPLACE)
        if res is EnjinItem:
            var item: EnjinItem = res
            var name := path.get_file().get_basename()
            if item.collection_id == collection_id:
                touched.append("%s (unchanged)" % name)
                continue
            item.collection_id = collection_id
            var save_err := ResourceSaver.save(item, path)
            if save_err != OK:
                push_warning("[StampCollectionId] Failed to save %s (err %s)" % [path, save_err])
                continue
            touched.append(name)
    for i in dir.get_subdir_count():
        _walk_fs(dir.get_subdir(i), collection_id, touched)


func _show(title: String, message: String) -> void:
    if _dialog == null or not is_instance_valid(_dialog):
        _dialog = AcceptDialog.new()
        EditorInterface.get_base_control().add_child(_dialog)
    _dialog.title = title
    _dialog.dialog_text = message
    _dialog.min_size = Vector2i(560, 240)
    _dialog.popup_centered()
