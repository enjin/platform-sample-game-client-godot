# One wallet token row in the backpack. Port of BackpackItemController.cs.
extends PanelContainer

var _item: EnjinItem
var _balance: int = 0
var _recipient: LineEdit
var _backpack: Control

@onready var icon: TextureRect = %Icon
@onready var name_label: Label = %NameLabel
@onready var balance_label: Label = %BalanceLabel
@onready var amount_spin: SpinBox = %AmountSpin
@onready var melt_button: Button = %MeltButton
@onready var transfer_button: Button = %TransferButton


func setup(token_account, recipient: LineEdit, backpack: Control) -> void:
	_recipient = recipient
	_backpack = backpack
	_balance = int(token_account.balance)
	var collection_id: String = token_account.token.collection.collection_id
	var token_id: String = token_account.token.token_id
	_item = EnjinManager.get_token(collection_id, token_id)
	if _item != null:
		name_label.text = _item.display_name
		icon.texture = _item.item_sprite
	else:
		# defensive: the manager pre-filters to known tokens
		name_label.text = "Token #%s" % token_id
	balance_label.text = "x %d" % _balance
	amount_spin.min_value = 1
	amount_spin.max_value = maxi(1, _balance)
	melt_button.pressed.connect(_on_melt)
	transfer_button.pressed.connect(_on_transfer)


func _on_melt() -> void:
	if _item == null:
		return
	_backpack.set_status("Melting %d x %s... (server finalization can take ~20s)"
		% [int(amount_spin.value), _item.display_name])
	_item.melt(int(amount_spin.value))


func _on_transfer() -> void:
	if _item == null:
		return
	var recipient := _recipient.text.strip_edges()
	if recipient.is_empty():
		_backpack.set_status("Enter a recipient address first.")
		return
	_backpack.set_status("Transferring %d x %s... (server finalization can take ~20s)"
		% [int(amount_spin.value), _item.display_name])
	_item.transfer(recipient, int(amount_spin.value))
