module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// Quests stay out of the way on a roleplay server.
//
// Ported from the ofmiceandcam98-eng/CyberpunkMP fork (Quests.reds), which is
// itself based on Tilted Phoques' CyberpunkMP.
//
// While connected, nothing the game's story uses to reach a player gets
// through: the "new quest" popup, objective updates, and phone calls. The quest
// engine itself still runs in the background, but nothing announces it, tracks
// it on screen, or calls anyone into it. Disconnecting gives single player back
// exactly as it was, because every check asks whether we're connected right now.

// The "new quest" / quest-updated popup.
@wrapMethod(JournalNotificationQueue)
private final func PushQuestNotification(questEntry: wref<JournalQuest>, state: gameJournalEntryState) -> Void {
    if MpQuestsSilenced() {
        return;
    }
    wrappedMethod(questEntry, state);
}

// "Objective completed" / "new objective".
@wrapMethod(JournalNotificationQueue)
private final func PushObjectiveQuestNotification(entry: wref<JournalEntry>) -> Void {
    if MpQuestsSilenced() {
        return;
    }
    wrappedMethod(entry);
}

// The incoming-call widget. Refused before it learns who's calling, so a call
// is never shown and then dismissed.
@wrapMethod(IncomingCallLogicController)
public final func SetCallInfo(contactName: script_ref<String>, contactEntry: wref<JournalContact>, journalMgr: wref<JournalManager>, isRejectable: Bool) -> Void {
    if MpQuestsSilenced() {
        return;
    }
    wrappedMethod(contactName, contactEntry, journalMgr, isRejectable);
}

// The phone itself: the single entry point quests use to start a call. Refusing
// here means no ringtone, no restriction and no hidden call the player can't end.
@wrapMethod(PhoneSystem)
private final func OnTriggerCall(request: ref<questTriggerCallRequest>) -> Void {
    if MpQuestsSilenced() {
        return;
    }
    wrappedMethod(request);
}

// An earlier version held the game's "a holocall is being set up" fact at 1 to
// keep Phantom Liberty's holocalls from starting. The game also refuses every
// conversation while that's set, so no vendor, ripperdoc or NPC would talk to
// you, and it was written into saves. This puts it back to 0 on connecting;
// story calls are still refused at the phone (above).
public func MpSilenceStoryHolocalls() -> Void {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if IsDefined(quests) && quests.GetFact(n"holo_setup_active") != 0 {
        quests.SetFact(n"holo_setup_active", 0);
    }
}

// Are we on a server right now? Asked every time, never cached.
public func MpQuestsSilenced() -> Bool {
    let network = GameInstance.GetNetworkWorldSystem();
    return IsDefined(network) && network.IsConnected();
}
