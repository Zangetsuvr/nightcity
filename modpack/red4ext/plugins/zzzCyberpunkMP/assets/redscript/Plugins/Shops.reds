module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.Ink.*

// Cyberware tiers and the car dealership. The server keeps both (prices,
// which tier you bought, which cars you own); this is the game's side.
//
// CYBERWARE TIERS. Each tier, bought at a ripperdoc, sets how much cyberware
// you can carry (your capacity) and the best quality of implant you may
// install: tier 1 Common up to tier 5 Legendary. The ripperdoc screen shows
// your tier and a button to buy the next one.
//
// THE DEALERSHIP. A car icon on the map. Stand at it and press the job key to
// browse; bought cars go to your garage (call them from your phone) and come
// back every time you join, even on a new save.

// ------------------------------------------------------------------ cyberware

public class MpCyberware extends ScriptableSystem {
    public let m_known: Bool;
    public let m_tier: Int32;
    public let m_capacity: Int32;
    public let m_maxQuality: Int32;
    public let m_nextPrice: Int32;
    private let m_modifier: ref<gameStatModifierData>;
    private let m_generation: Int32;

    public static func Get() -> ref<MpCyberware> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpCyberware") as MpCyberware;
    }

    public func Set(tier: Int32, capacity: Int32, maxQuality: Int32, nextPrice: Int32) -> Void {
        this.m_known = true;
        this.m_tier = tier;
        this.m_capacity = capacity;
        this.m_maxQuality = maxQuality;
        this.m_nextPrice = nextPrice;
        this.Apply();
        // Level-ups and perks change the game's own capacity; keep ours on top.
        this.m_generation += 1;
        this.ScheduleReapply();
    }

    // Sets the capacity stat to the tier's number, whatever the game's own is.
    public func Apply() -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) || !this.m_known {
            return;
        }
        let stats = GameInstance.GetStatsSystem(this.GetGameInstance());
        let id = Cast<StatsObjectID>(player.GetEntityID());
        if IsDefined(this.m_modifier) {
            stats.RemoveModifier(id, this.m_modifier);
            this.m_modifier = null;
        }
        let own = stats.GetStatValue(id, gamedataStatType.Humanity);
        let difference = Cast<Float>(this.m_capacity) - own;
        if AbsF(difference) < 0.01 {
            return;
        }
        this.m_modifier = RPGManager.CreateStatModifier(gamedataStatType.Humanity, gameStatModifierType.Additive, difference);
        stats.AddModifier(id, this.m_modifier);
    }

    private func ScheduleReapply() -> Void {
        let again = new MpCyberwareReapply();
        again.generation = this.m_generation;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(again, 30.0, false);
    }

    public func Reapply(generation: Int32) -> Void {
        if generation != this.m_generation {
            return;
        }
        if !MpWorldKeepsRunning() {
            return;
        }
        this.Apply();
        this.ScheduleReapply();
    }

    public func QualityName(rank: Int32) -> String {
        switch rank {
            case 1: return "Common";
            case 2: return "Uncommon";
            case 3: return "Rare";
            case 4: return "Epic";
        }
        return "Legendary";
    }
}

public class MpCyberwareReapply extends DelayCallback {
    public let generation: Int32;

    public func Call() -> Void {
        let cyberware = MpCyberware.Get();
        if IsDefined(cyberware) {
            cyberware.Reapply(this.generation);
        }
    }
}

// Common 1, Uncommon 2, Rare 3, Epic 4, Legendary and Iconic 5.
public func MpQualityRank(quality: gamedataQuality) -> Int32 {
    switch quality {
        case gamedataQuality.Common:
        case gamedataQuality.CommonPlus:
            return 1;
        case gamedataQuality.Uncommon:
        case gamedataQuality.UncommonPlus:
            return 2;
        case gamedataQuality.Rare:
        case gamedataQuality.RarePlus:
            return 3;
        case gamedataQuality.Epic:
        case gamedataQuality.EpicPlus:
            return 4;
    }
    return 5;
}

// No installing implants above your tier's quality.
@wrapMethod(RipperDocGameController)
private final func EquipCyberware(itemData: wref<gameItemData>) -> Bool {
    let cyberware = MpCyberware.Get();
    if MpWorldKeepsRunning() && IsDefined(cyberware) && cyberware.m_known && IsDefined(itemData) {
        let rank = MpQualityRank(RPGManager.GetItemQuality(itemData));
        if rank > cyberware.m_maxQuality {
            MpJobMessage("Your cyberware tier (" + IntToString(cyberware.m_tier) + ") only allows " + cyberware.QualityName(cyberware.m_maxQuality)
                + " implants. Upgrade your tier to install this one.");
            // Leave the screen the way the game does after a refused install;
            // otherwise it thinks a confirmation is still open and won't close.
            this.m_hoverArea = gamedataEquipmentArea.Invalid;
            this.m_isPurchaseEquip = false;
            this.m_isInEquipPopup = false;
            this.m_audioSystem.Play(n"ui_menu_attributes_fail");
            return false;
        }
    }
    return wrappedMethod(itemData);
}

// The tier panel on the ripperdoc screen, top right.
@addField(RipperDocGameController)
let m_mpTierPanel: ref<inkCanvas>;

@wrapMethod(RipperDocGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpWorldKeepsRunning() {
        this.MpDrawTierPanel();
    }
    return result;
}

@addMethod(RipperDocGameController)
public func MpDrawTierPanel() -> Void {
    let cyberware = MpCyberware.Get();
    let root = this.GetRootCompoundWidget();
    if !IsDefined(cyberware) || !cyberware.m_known || !IsDefined(root) {
        return;
    }
    if IsDefined(this.m_mpTierPanel) {
        root.RemoveChild(this.m_mpTierPanel);
    }
    let panel = new inkCanvas();
    panel.SetName(n"mp_cyberware_tier");
    panel.SetAnchor(inkEAnchor.TopRight);
    panel.SetAnchorPoint(new Vector2(1.0, 0.0));
    panel.SetMargin(new inkMargin(0.0, 140.0, 120.0, 0.0));
    panel.SetSize(new Vector2(760.0, 250.0));
    panel.Reparent(root);
    this.m_mpTierPanel = panel;

    MpJbRect(panel, 0.0, 0.0, 760.0, 250.0, MpJbPlate(), 0.92);
    MpJbRect(panel, 0.0, 0.0, 760.0, 4.0, MpJbRed(), 1.0);
    MpJbText(panel, 30.0, 22.0, "CYBERWARE TIER " + IntToString(cyberware.m_tier), 44, n"Bold", MpJbRed());
    MpJbText(panel, 30.0, 80.0, "Capacity " + IntToString(cyberware.m_capacity) + "  -  implants up to " + cyberware.QualityName(cyberware.m_maxQuality), 30, n"Medium", MpJbInk());

    if cyberware.m_nextPrice > 0 {
        let button = new inkCanvas();
        button.SetName(n"mp_tier_buy");
        button.SetAnchor(inkEAnchor.TopLeft);
        button.SetMargin(new inkMargin(30.0, 140.0, 0.0, 0.0));
        button.SetSize(new Vector2(700.0, 76.0));
        button.SetInteractive(true);
        button.Reparent(panel);
        MpJbRect(button, 0.0, 0.0, 700.0, 76.0, MpJbRed(), 0.85);
        MpJbText(button, 24.0, 16.0, "UPGRADE TO TIER " + IntToString(cyberware.m_tier + 1) + "  -  " + IntToString(cyberware.m_nextPrice) + " EDDIES", 34, n"Bold", MpJbPlate());
        button.RegisterToCallback(n"OnRelease", this, n"OnMpTierBuy");
    } else {
        MpJbText(panel, 30.0, 150.0, "Highest tier.", 30, n"Medium", MpJbGold());
    }
}

@addMethod(RipperDocGameController)
protected cb func OnMpTierBuy(e: ref<inkPointerEvent>) -> Bool {
    if e.IsAction(n"click") {
        CharacterServer.BuyCyberwareTier();
        // The server answers with the new tier; redraw once it has.
        let redraw = new MpRedrawTierPanel();
        redraw.controller = this;
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(redraw, 0.6, false);
    }
    return true;
}

public class MpRedrawTierPanel extends DelayCallback {
    public let controller: wref<RipperDocGameController>;

    public func Call() -> Void {
        if IsDefined(this.controller) {
            this.controller.MpDrawTierPanel();
        }
    }
}

// ------------------------------------------------------------------ dealership

public class MpCarOffer {
    public let record: String;
    public let name: String;
    public let price: Int32;
}

public class MpDealership extends ScriptableSystem {
    public let m_name: String;
    public let m_position: Vector4;
    public let m_known: Bool;
    public let m_cars: array<ref<MpCarOffer>>;
    // Cars the server listed, including ones this game doesn't have.
    public let m_offered: Int32;
    // Shop prices from the server's prices.json.
    public let m_priceKnown: Bool;
    public let m_globalMultiplier: Float;
    public let m_categoryNames: array<String>;
    public let m_categoryMultipliers: array<Float>;
    public let m_itemIDs: array<TweakDBID>;
    public let m_itemPrices: array<Int32>;
    private let m_mappin: NewMappinID;
    private let m_hasMappin: Bool;
    private let m_markers: array<NewMappinID>;

    public static func Get() -> ref<MpDealership> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpDealership") as MpDealership;
    }

    public func Load(payload: String) -> Void {
        ArrayClear(this.m_cars);
        this.m_offered = 0;
        ArrayClear(this.m_categoryNames);
        ArrayClear(this.m_categoryMultipliers);
        ArrayClear(this.m_itemIDs);
        ArrayClear(this.m_itemPrices);
        this.m_globalMultiplier = 1.0;
        let mappins = GameInstance.GetMappinSystem(this.GetGameInstance());
        for id in this.m_markers {
            mappins.UnregisterMappin(id);
        }
        ArrayClear(this.m_markers);
        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            if ArraySize(f) >= 5 && Equals(f[0], "D") {
                this.m_name = f[1];
                this.m_position = new Vector4(StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]), 1.0);
                this.m_known = true;
            } else {
                if ArraySize(f) >= 2 && Equals(f[0], "PG") {
                    this.m_globalMultiplier = StringToFloat(f[1]);
                    this.m_priceKnown = true;
                }
                if ArraySize(f) >= 3 && Equals(f[0], "PC") {
                    ArrayPush(this.m_categoryNames, f[1]);
                    ArrayPush(this.m_categoryMultipliers, StringToFloat(f[2]));
                }
                if ArraySize(f) >= 3 && Equals(f[0], "PI") {
                    ArrayPush(this.m_itemIDs, TDBID.Create(f[1]));
                    ArrayPush(this.m_itemPrices, StringToInt(f[2]));
                }
                if ArraySize(f) >= 6 && Equals(f[0], "M") {
                    let position = new Vector4(StringToFloat(f[3]), StringToFloat(f[4]), StringToFloat(f[5]), 1.0);
                    ArrayPush(this.m_markers, MpRegisterMapIcon(MpMarkerVariant(f[1]), position));
                }
                if ArraySize(f) >= 4 && Equals(f[0], "V") {
                    this.m_offered += 1;
                    // Only cars this version of the game actually has.
                    if IsDefined(TweakDBInterface.GetVehicleRecord(TDBID.Create(f[1]))) {
                        let car = new MpCarOffer();
                        car.record = f[1];
                        car.name = f[2];
                        car.price = StringToInt(f[3]);
                        ArrayPush(this.m_cars, car);
                    }
                }
            }
        }
        this.PlaceMappin();
        this.Watch();
    }

    private func PlaceMappin() -> Void {
        let mappins = GameInstance.GetMappinSystem(this.GetGameInstance());
        if this.m_hasMappin {
            mappins.UnregisterMappin(this.m_mappin);
            this.m_hasMappin = false;
        }
        if !this.m_known {
            return;
        }
        this.m_mappin = MpRegisterMapIcon(gamedataMappinVariant.Zzz01_CarForPurchaseVariant, this.m_position);
        this.m_hasMappin = true;
    }

    public func ServerPrice(itemID: ItemID, gamePrice: Int32) -> Int32 {
        let record = ItemID.GetTDBID(itemID);
        let i = 0;
        while i < ArraySize(this.m_itemIDs) {
            if this.m_itemIDs[i] == record {
                return this.m_itemPrices[i];
            }
            i += 1;
        }
        let multiplier = this.m_globalMultiplier;
        let category = ToString(RPGManager.GetItemCategory(itemID));
        i = 0;
        while i < ArraySize(this.m_categoryNames) {
            if Equals(this.m_categoryNames[i], category) {
                multiplier *= this.m_categoryMultipliers[i];
            }
            i += 1;
        }
        return Max(1, RoundF(Cast<Float>(gamePrice) * multiplier));
    }

    public func IsNear(player: ref<GameObject>) -> Bool {
        if !this.m_known || !IsDefined(player) {
            return false;
        }
        return Vector4.Distance(player.GetWorldPosition(), this.m_position) < 12.0;
    }

    // Walking up to the dealership: say how to open it, once per visit.
    private let m_hinted: Bool;
    private let m_watching: Bool;

    public func Watch() -> Void {
        if this.m_watching {
            return;
        }
        this.m_watching = true;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(new MpDealershipWatch(), 1.0, false);
    }

    public func CheckNear() -> Void {
        let near = this.IsNear(GetPlayer(this.GetGameInstance())) && ArraySize(this.m_cars) > 0;
        if near && !this.m_hinted {
            this.m_hinted = true;
            MpJobMessage(this.m_name + ": press your job board key or type /dealer to browse cars.");
        }
        if !near {
            this.m_hinted = false;
        }
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(new MpDealershipWatch(), 1.0, false);
    }

    // /dealer in chat: what the game knows about the dealership.
    public func Describe() -> String {
        if !this.m_known {
            return "Dealership: the server hasn't sent it yet (rejoin).";
        }
        let player = GetPlayer(this.GetGameInstance());
        let distance = IsDefined(player) ? Vector4.Distance(player.GetWorldPosition(), this.m_position) : -1.0;
        return "Dealership at " + FloatToStringPrec(this.m_position.X, 1) + ", " + FloatToStringPrec(this.m_position.Y, 1) + ", " + FloatToStringPrec(this.m_position.Z, 1)
            + "  |  you're " + FloatToStringPrec(distance, 1) + " m away (needs < 12)  |  cars: " + IntToString(ArraySize(this.m_cars)) + " of " + IntToString(this.m_offered) + " exist in this game";
    }
}

public func MpUnlockVehicles(records: String) -> Void {
    let vehicles = GameInstance.GetVehicleSystem(GetGameInstance());
    for record in StrSplit(records, "|") {
        if StrLen(record) > 0 && IsDefined(TweakDBInterface.GetVehicleRecord(TDBID.Create(record))) {
            vehicles.EnablePlayerVehicle(record, true, false);
        }
    }
}

// A fixed icon that shows on the world map and minimap, like the game's own
// drop points.
public func MpRegisterMapIcon(variant: gamedataMappinVariant, position: Vector4) -> NewMappinID {
    let data: MappinData;
    data.mappinType = t"Mappins.DropPointStaticMappin";
    data.variant = variant;
    data.active = true;
    data.visibleThroughWalls = false;
    return GameInstance.GetMappinSystem(GetGameInstance()).RegisterMappin(data, position);
}

public func MpMarkerVariant(kind: String) -> gamedataMappinVariant {
    let k = StrLower(kind);
    if Equals(k, "ripperdoc") { return gamedataMappinVariant.ServicePointRipperdocVariant; }
    if Equals(k, "clothes") { return gamedataMappinVariant.ServicePointClothesVariant; }
    if Equals(k, "food") { return gamedataMappinVariant.ServicePointFoodVariant; }
    if Equals(k, "bar") { return gamedataMappinVariant.ServicePointBarVariant; }
    if Equals(k, "meds") { return gamedataMappinVariant.ServicePointMedsVariant; }
    if Equals(k, "tech") { return gamedataMappinVariant.ServicePointTechVariant; }
    if Equals(k, "junk") { return gamedataMappinVariant.ServicePointJunkVariant; }
    if Equals(k, "netrunner") { return gamedataMappinVariant.ServicePointNetTrainerVariant; }
    if Equals(k, "melee") { return gamedataMappinVariant.ServicePointMeleeTrainerVariant; }
    if Equals(k, "dropoff") { return gamedataMappinVariant.ServicePointDropPointVariant; }
    if Equals(k, "blackmarket") { return gamedataMappinVariant.Zzz14_ServicePointBlackMarketVariant; }
    if Equals(k, "car") { return gamedataMappinVariant.Zzz01_CarForPurchaseVariant; }
    return gamedataMappinVariant.ServicePointGunsVariant;
}

// ------------------------------------------------------------------ shop prices

// What a shop item costs on the server: a fixed price from prices.json if it
// has one, otherwise the game's own price times the category and global
// multipliers. Used for what the shop shows and for what you're charged.
@wrapMethod(MarketSystem)
public final static func GetBuyPrice(vendorObject: wref<GameObject>, itemID: ItemID) -> Int32 {
    let price = wrappedMethod(vendorObject, itemID);
    let shops = MpDealership.Get();
    if !MpWorldKeepsRunning() || !IsDefined(shops) || !shops.m_priceKnown {
        return price;
    }
    return shops.ServerPrice(itemID, price);
}

public class MpDealershipWatch extends DelayCallback {
    public func Call() -> Void {
        let dealer = MpDealership.Get();
        if IsDefined(dealer) {
            dealer.CheckNear();
        }
    }
}
