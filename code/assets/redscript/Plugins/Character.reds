module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

// Money and progress are owned by the server (CharacterSystem plugin).
// The game never decides how many eddies a player has: it only shows what the
// server sends. Anything the game adds or removes on its own is undone at the
// next sync, and big jumps are reported to the server as possible cheating.

public native class CharacterServer extends ServerRpc {
    // Ask the server to send balance and progress again.
    public static native func RequestSync() -> Void;

    // Tell the server our eddies changed without its say-so (cheat detection).
    public static native func ReportLocalBalance(localBalance: Int64, lastFromServer: Int64) -> Void;

    // Say which lifepath this character was made with. The server hands out that
    // lifepath's starter kit the first time, and ignores it after that.
    public static native func ClaimStarterKit(lifepath: Int32) -> Void;

    // Move up one cyberware tier (Plugins/Shops.reds).
    public static native func BuyCyberwareTier() -> Void;

    // Buy a car at the dealership (Plugins/Shops.reds).
    public static native func BuyVehicle(record: String) -> Void;
}

// Holds what the server last told us. Client RPC functions don't run on a
// lasting object, so state lives in this game system instead.
public class CharacterState extends ScriptableSystem {
    public let lastBalance: Int64;
    public let hasBalance: Bool;
    public let level: Int32;
    public let xp: Int64;
    public let nextLevelXp: Int64;

    public static func Get(game: GameInstance) -> ref<CharacterState> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"CyberpunkMP.Plugins.CharacterState") as CharacterState;
    }
}

public class CharacterClient extends ClientRpc {
    // Make the eddies in the player's inventory match the server's balance.
    public func SetBalance(balance: Int64) -> Void {
        let game = GetGameInstance();
        let player = GetPlayer(game);
        let state = CharacterState.Get(game);
        if !IsDefined(player) || !IsDefined(state) {
            return;
        }

        let ts = GameInstance.GetTransactionSystem(game);
        let current = Cast<Int64>(ts.GetItemQuantity(player, MarketSystem.Money()));

        // If our eddies moved since the server's last update, something other
        // than the server changed them (a cheat, a console command, a vendor).
        // Report it; the server decides whether it's worth flagging.
        if state.hasBalance && current != state.lastBalance {
            CharacterServer.ReportLocalBalance(current, state.lastBalance);
        }
        state.lastBalance = balance;
        state.hasBalance = true;

        let diff = balance - current;
        if diff > 0l {
            ts.GiveItem(player, MarketSystem.Money(), Cast<Int32>(diff));
        } else {
            if diff < 0l {
                ts.RemoveItem(player, MarketSystem.Money(), Cast<Int32>(-diff));
            }
        }
    }

    // Move the player (the server does this once for a brand-new character,
    // out of the clean start's holding room to the server's start point).
    public func Teleport(x: Float, y: Float, z: Float, yaw: Float) -> Void {
        let game = GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return;
        }
        let facing: EulerAngles;
        facing.Yaw = yaw;
        GameInstance.GetTeleportationFacility(game).Teleport(player, new Vector4(x, y, z, 1.0), facing);
        MpSaveAfter(8.0);
    }

    // A brand-new character's starter kit, from the server: "item,quantity,equip"
    // entries separated by "|". What the clean start left the character carrying
    // goes first, so everyone starts from the same place.
    public func GiveStarterKit(items: String) -> Void {
        let game = GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return;
        }
        MpStripStartingGear(player);

        let ts = GameInstance.GetTransactionSystem(game);
        let equipment = EquipmentSystem.GetInstance(player);
        for entry in StrSplit(items, "|") {
            MpGiveKitItem(player, entry, ts, equipment);
        }
        // Into the save, so the kit is still there next time.
        MpSaveAfter(5.0);
    }

    // Cyberware tier from the server: capacity, best implant quality (1-5) and
    // what the next tier costs (0 = at the top).
    public func SetCyberware(tier: Int32, capacity: Int32, maxQuality: Int32, nextPrice: Int32) -> Void {
        let cyberware = MpCyberware.Get();
        if IsDefined(cyberware) {
            cyberware.Set(tier, capacity, maxQuality, nextPrice);
        }
    }

    // Where the dealership is and what it sells.
    public func ShopData(payload: String) -> Void {
        let dealership = MpDealership.Get();
        if IsDefined(dealership) {
            dealership.Load(payload);
        }
    }

    // Cars this character owns ("|"-separated records): into the garage.
    public func UnlockVehicles(records: String) -> Void {
        MpUnlockVehicles(records);
    }

    // Street Cred level and XP from the server, kept for UI to read later.
    public func SetProgress(level: Int32, xp: Int64, nextLevelXp: Int64) -> Void {
        let state = CharacterState.Get(GetGameInstance());
        if !IsDefined(state) {
            return;
        }
        state.level = level;
        state.xp = xp;
        state.nextLevelXp = nextLevelXp;
    }
}

// Takes away the clothes, weapons, grenades, ammo and consumables a new character
// arrives with. Quest items, cyberware, money and the player's fists stay.
public func MpStripStartingGear(player: ref<PlayerPuppet>) -> Void {
    let ts = GameInstance.GetTransactionSystem(player.GetGame());
    let items: array<wref<gameItemData>>;
    ts.GetItemList(player, items);

    let remove: array<ItemID>;
    for data in items {
        if MpIsStartingGear(data) {
            ArrayPush(remove, data.GetID());
        }
    }
    for id in remove {
        ts.RemoveItem(player, id, ts.GetItemQuantity(player, id));
    }
}

public func MpIsStartingGear(data: wref<gameItemData>) -> Bool {
    if !IsDefined(data) || data.HasTag(n"Quest") || data.HasTag(n"base_fists") || data.HasTag(n"Currency") {
        return false;
    }
    let category = RPGManager.GetItemCategory(data.GetID());
    return Equals(data.GetItemType(), gamedataItemType.Con_Ammo)
        || Equals(category, gamedataItemCategory.Clothing) || Equals(category, gamedataItemCategory.Weapon)
        || Equals(category, gamedataItemCategory.Gadget) || Equals(category, gamedataItemCategory.Consumable);
}

// One "item,quantity,equip" entry of a starter kit. Kept out of CharacterClient:
// every function in an RPC class is treated as a call the server can make.
public func MpGiveKitItem(player: ref<PlayerPuppet>, entry: String, ts: ref<TransactionSystem>, equipment: ref<EquipmentSystem>) -> Void {
    let parts = StrSplit(entry, ",");
    if ArraySize(parts) < 3 {
        return;
    }
    let record = TDBID.Create(parts[0]);
    let quantity = StringToInt(parts[1]);
    if !IsDefined(TweakDBInterface.GetItemRecord(record)) || quantity <= 0 {
        return;
    }
    ts.GiveItem(player, ItemID.FromTDBID(record), quantity);
    if Equals(parts[2], "1") {
        let data = ts.GetItemDataByTDBID(player, record);
        if IsDefined(data) && ItemID.IsValid(data.GetID()) {
            let equip = new EquipRequest();
            equip.owner = player;
            equip.itemID = data.GetID();
            equip.addToInventory = false;
            equipment.QueueRequest(equip);
        }
    }
}
