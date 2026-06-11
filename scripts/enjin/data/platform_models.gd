# Plain-data port of HappyHarvest.EnjinIntegration.Data.PlatformModels.
#
# Source: Assets/Enjin Integration/Scripts/Data/PlatformModels.cs in the Unity
# client. These classes mirror the JSON shape returned by the C# game server
# (see ../platform-sample-game-server) for the /api/wallet/get-tokens endpoint.
#
# We use RefCounted helpers with `from_dict` factories so they can be constructed
# directly from JSON.parse_string() output without manual field-by-field copying
# at every call site.

class_name PlatformModels
extends RefCounted


# Token ids on the platform are arbitrary-precision integers. In JSON they
# arrive as strings, and on the wire to /api/token/* we send them as strings.
# We keep them as `String` here; if you ever need arithmetic, parse on demand.
# The class exists to keep call sites symmetric with the Unity port
# (SerializableBigInteger) and to centralise stringification.
class SerializableBigInteger extends RefCounted:
    var value: String = "-1"

    func _init(initial: Variant = "-1") -> void:
        if initial == null:
            value = "-1"
        else:
            value = str(initial)

    func _to_string() -> String:
        return value

    func equals(other: SerializableBigInteger) -> bool:
        return other != null and other.value == value


class Account extends RefCounted:
    var public_key: String = ""
    var address: String = ""

    static func from_dict(d: Dictionary) -> Account:
        if d == null or d.is_empty():
            return null
        var a := Account.new()
        a.public_key = d.get("publicKey", "")
        a.address = d.get("address", "")
        return a

    func _to_string() -> String:
        return "Account | Address: %s, PublicKey: %s" % [address, public_key]


class Attribute extends RefCounted:
    var key: String = ""
    var value: String = ""

    static func from_dict(d: Dictionary) -> Attribute:
        var a := Attribute.new()
        a.key = d.get("key", "")
        a.value = d.get("value", "")
        return a

    func _to_string() -> String:
        return "%s: %s" % [key, value]


class Collection extends RefCounted:
    var collection_id: String = ""

    static func from_dict(d: Dictionary) -> Collection:
        if d == null or d.is_empty():
            return null
        var c := Collection.new()
        c.collection_id = d.get("collectionId", "")
        return c

    func _to_string() -> String:
        return "Collection ID: %s" % collection_id


class Token extends RefCounted:
    var collection: Collection = null
    var token_id: String = ""
    var attributes: Array = []  # Array[Attribute]

    static func from_dict(d: Dictionary) -> Token:
        if d == null or d.is_empty():
            return null
        var t := Token.new()
        t.collection = Collection.from_dict(d.get("collection", {}))
        t.token_id = d.get("tokenId", "")
        var attrs: Array = []
        for raw in d.get("attributes", []):
            if raw is Dictionary:
                attrs.append(Attribute.from_dict(raw))
        t.attributes = attrs
        return t


class TokenAccount extends RefCounted:
    var balance: String = "0"
    var token: Token = null

    static func from_dict(d: Dictionary) -> TokenAccount:
        var ta := TokenAccount.new()
        # Balance can arrive as int or string depending on serializer settings;
        # normalise to string to match the Unity port's behaviour.
        ta.balance = str(d.get("balance", "0"))
        ta.token = Token.from_dict(d.get("token", {}))
        return ta


class ManagedWalletAccount extends RefCounted:
    var account: Account = null
    var token_accounts: Array = []  # Array[TokenAccount]

    static func from_dict(d: Dictionary) -> ManagedWalletAccount:
        if d == null:
            return null
        var w := ManagedWalletAccount.new()
        w.account = Account.from_dict(d.get("account", {}))
        var tas: Array = []
        for raw in d.get("tokenAccounts", []):
            if raw is Dictionary:
                tas.append(TokenAccount.from_dict(raw))
        w.token_accounts = tas
        return w
