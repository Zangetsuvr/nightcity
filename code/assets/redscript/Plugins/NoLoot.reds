module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// No free loot while connected: everything you own is bought, earned from a
// job, or given by the server. Containers, dropped items, loot bags and bodies
// come up empty, and their "take" prompts are hidden.

public func MpNoLoot() -> Bool {
    return MpWorldKeepsRunning();
}

// Empty a loot source once the player gets near it.
public func MpEmptyLoot(target: ref<GameObject>, activator: ref<GameObject>) -> Void {
    if !MpNoLoot() || !IsDefined(target) || !IsDefined(activator) || !activator.IsPlayer() {
        return;
    }
    // A moment later, not inside the game's own handler: emptying an item on
    // the ground removes it from the world, which mustn't happen mid-callback.
    let later = new MpEmptyLootLater();
    later.target = target;
    GameInstance.GetDelaySystem(target.GetGame()).DelayCallback(later, 0.1, false);
}

public class MpEmptyLootLater extends DelayCallback {
    public let target: wref<GameObject>;

    public func Call() -> Void {
        let target = this.target;
        if IsDefined(target) && MpNoLoot() {
            MpTrace("emptying loot");
            GameInstance.GetTransactionSystem(target.GetGame()).RemoveAllItems(target);
        }
    }
}

// Every "take/loot/eat/read" prompt on anything's inventory (bodies included).
@wrapMethod(Inventory)
public final func IsChoiceAvailable(itemActionRecord: ref<ItemAction_Record>, requester: ref<GameObject>, ownerEntID: EntityID, itemID: ItemID) -> gameinteractionsELootChoiceType {
    if MpNoLoot() && IsDefined(requester) && requester.IsPlayer() {
        return gameinteractionsELootChoiceType.Invisible;
    }
    return wrappedMethod(itemActionRecord, requester, ownerEntID, itemID);
}

// "Loot all" on a body.
@wrapMethod(ScriptedPuppet)
private final func LootAllItems(choiceEvent: ref<InteractionChoiceEvent>) {
    if MpNoLoot() {
        return;
    }
    wrappedMethod(choiceEvent);
}

// Items lying on the ground (also stops ammo auto-pickup).
@wrapMethod(gameLootObject)
protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {
    MpEmptyLoot(this, evt.activator);
    return wrappedMethod(evt);
}

// Crates, lockers, stashes in the world.
@wrapMethod(gameContainerObjectBase)
protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {
    MpEmptyLoot(this, evt.activator);
    return wrappedMethod(evt);
}

// Loot bags left by dead NPCs.
@wrapMethod(gameLootBag)
protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {
    MpEmptyLoot(this, evt.activator);
    return wrappedMethod(evt);
}
