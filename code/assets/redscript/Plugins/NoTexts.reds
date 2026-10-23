module CyberpunkMP.Plugins

// No story texts on the server.
//
// Fixers, vendors and story characters still write to you in the background
// (gig offers, "your iron's ready", sales). Their pop-ups are already refused
// (NoActivities.reds); this keeps them out of the phone's message list and off
// the unread counter on the HUD. Single player is untouched.

@wrapMethod(MessengerUtils)
public final static func GetSimpleContactDataArray(journal: ref<JournalManager>, includeUnknown: Bool, skipEmpty: Bool, includeWithNoUnread: Bool, opt activeDataSync: wref<MessengerContactSyncData>) -> array<ref<IScriptable>> {
    if MpQuestsSilenced() {
        let none: array<ref<IScriptable>>;
        return none;
    }
    return wrappedMethod(journal, includeUnknown, skipEmpty, includeWithNoUnread, activeDataSync);
}

@wrapMethod(MessengerUtils)
public final static func GetMessageDataArrayForContact(journal: ref<JournalManager>, concactHash: Int32, includeUnknown: Bool, skipEmpty: Bool, opt activeDataSync: wref<MessengerContactSyncData>) -> array<ref<IScriptable>> {
    if MpQuestsSilenced() {
        let none: array<ref<IScriptable>>;
        return none;
    }
    return wrappedMethod(journal, concactHash, includeUnknown, skipEmpty, activeDataSync);
}

// The unread-message number and quest marker on the phone icon.
@wrapMethod(PhoneHotkeyController)
private final func UpdateData() -> Void {
    if MpQuestsSilenced() {
        inkWidgetRef.SetVisible(this.messageCounterLabel, false);
        inkWidgetRef.SetVisible(this.messageCounterLabelCircle, false);
        inkWidgetRef.SetVisible(this.questIcon, false);
        inkWidgetRef.SetVisible(this.callIcon, false);
        return;
    }
    wrappedMethod();
}
