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

// Bodies: the game shows their loot list without asking the prompt check
// above, so their pockets are emptied instead (everything but what they wear).
public func MpStripBody(target: ref<GameObject>) -> Void {
    if !MpNoLoot() || !IsDefined(target) || target.IsPlayer() {
        return;
    }
    let later = new MpStripBodyLater();
    later.target = target;
    GameInstance.GetDelaySystem(target.GetGame()).DelayCallback(later, 0.5, false);
}

public class MpStripBodyLater extends DelayCallback {
    public let target: wref<GameObject>;

    public func Call() -> Void {
        let target = this.target;
        if !IsDefined(target) || !MpNoLoot() {
            return;
        }
        let ts = GameInstance.GetTransactionSystem(target.GetGame());
        let items: array<wref<gameItemData>>;
        ts.GetItemList(target, items);
        let remove: array<ItemID>;
        let amounts: array<Int32>;
        for data in items {
            if IsDefined(data) {
                let id = data.GetID();
                if NotEquals(RPGManager.GetItemCategory(id), gamedataItemCategory.Clothing) {
                    ArrayPush(remove, id);
                    ArrayPush(amounts, data.GetQuantity());
                }
            }
        }
        let i = 0;
        while i < ArraySize(remove) {
            ts.RemoveItem(target, remove[i], amounts[i]);
            i += 1;
        }
    }
}

// Killed: empty the body once the game has filled its pockets.
@wrapMethod(NPCPuppet)
protected cb func OnDeath(evt: ref<gameDeathEvent>) -> Bool {
    let result = wrappedMethod(evt);
    MpStripBody(this);
    return result;
}

// Knocked out, or a body from before: empty it when the player gets near.
@wrapMethod(ScriptedPuppet)
protected cb func OnInteractionActivated(evt: ref<InteractionActivationEvent>) -> Bool {
    if IsDefined(evt.activator) && evt.activator.IsPlayer() && !ScriptedPuppet.IsActive(this) {
        MpStripBody(this);
    }
    return wrappedMethod(evt);
}

// Ammo and other items dropped on the ground (an NPC's ammo when it dies, a
// dropped weapon): walking over them picks them up automatically, before the
// interaction check above can empty them. So they're emptied as they appear.
@wrapMethod(gameItemDropObject)
protected cb func OnGameAttached() -> Bool {
    let result = wrappedMethod();
    if MpNoLoot() {
        let soon = new MpEmptyLootLater();
        soon.target = this;
        GameInstance.GetDelaySystem(this.GetGame()).DelayCallback(soon, 0.2, false);
        // Contents are sometimes filled in a moment after it appears.
        let later = new MpEmptyLootLater();
        later.target = this;
        GameInstance.GetDelaySystem(this.GetGame()).DelayCallback(later, 1.0, false);
    }
    return result;
}

// The game's "you're low, here's some ammo / a heal" drops from enemies.
@wrapMethod(PlayerHandicapSystem)
public const final func CanDropAmmo() -> Bool {
    if MpNoLoot() {
        return false;
    }
    return wrappedMethod();
}

@wrapMethod(PlayerHandicapSystem)
public const final func CanDropHealingConsumable() -> Bool {
    if MpNoLoot() {
        return false;
    }
    return wrappedMethod();
}
