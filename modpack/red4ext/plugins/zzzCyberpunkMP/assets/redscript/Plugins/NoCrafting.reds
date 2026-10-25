module CyberpunkMP.Plugins

// No crafting on the server, for now.
//
// The crafting tab is greyed out in the hub menu (the same way the game does it
// during combat) and crafting or upgrading an item does nothing. Single player
// keeps crafting.

@wrapMethod(HubMenuUtility)
public final static func IsCraftingAvailable(player: wref<PlayerPuppet>) -> Bool {
    if MpWorldKeepsRunning() {
        return false;
    }
    return wrappedMethod(player);
}

@wrapMethod(CraftingSystem)
private final func CraftItem(target: wref<GameObject>, itemRecord: ref<Item_Record>, amount: Int32, opt ammoBulletAmount: Int32) -> wref<gameItemData> {
    if MpWorldKeepsRunning() {
        return null;
    }
    return wrappedMethod(target, itemRecord, amount, ammoBulletAmount);
}

@wrapMethod(CraftingSystem)
private final func UpgradeItem(owner: wref<GameObject>, itemID: ItemID) -> Void {
    if MpWorldKeepsRunning() {
        return;
    }
    wrappedMethod(owner, itemID);
}
