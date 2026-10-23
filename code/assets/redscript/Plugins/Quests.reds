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

// Phantom Liberty's holocalls (Songbird and the rest) are scenes the quest
// drives, so blocking the phone can't stop them. They all wait on the game's
// own "a holocall is being set up" flag; holding it at 1 keeps every one of them
// from starting. Set when connecting; written into the save on purpose, so a
// story call isn't left armed for this character later.
public func MpSilenceStoryHolocalls() -> Void {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if IsDefined(quests) {
        quests.SetFact(n"holo_setup_active", 1);
    }
}

// Are we on a server right now? Asked every time, never cached.
public func MpQuestsSilenced() -> Bool {
    let network = GameInstance.GetNetworkWorldSystem();
    return IsDefined(network) && network.IsConnected();
}
