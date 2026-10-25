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

// (The incoming-call widget used to be refused here too. A call that was
// already ringing when we connected then had a half-set-up widget, and the game
// crashed when that call moved into the phone. Calls are now stopped before
// they start, below, from the moment the game is started by the launcher.)

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

// Are we playing on a server? True once the game was started by the launcher
// (so a new character's first seconds, before connecting, are quiet too) and
// while connected. Asked every time, never cached.
public func MpQuestsSilenced() -> Bool {
    let network = GameInstance.GetNetworkWorldSystem();
    return IsDefined(network) && (network.IsConnected() || network.HasServerSession());
}

// Opens the world on a clean start.
//
// The game's start-up quest has a separate entrance for Phantom Liberty starts,
// which our clean start uses. On that entrance it waits for three internal flags
// (normally set by Phantom Liberty's own start-up, which the clean start leaves
// out) before it switches on the open world: vendors, ripperdocs, fixers, fast
// travel, the metro. The vendors then also wait for "prologue done" and "side
// content allowed". Setting these starts none of the story.
public func MpOpenWorld() -> Void {
    let quests = GameInstance.GetQuestsSystem(GetGameInstance());
    if !IsDefined(quests) {
        return;
    }
    // The ripperdoc screen also counts as a first-visit tutorial (which can't be
    // closed until finished) unless these say it's been seen.
    let facts: array<CName> = [n"CYB-629334", n"CYB-624820", n"CYB-655031", n"q000_done", n"q101_enable_side_content", n"ep1_side_content",
        n"ep1_ripperdoc_tutorial_seen", n"q001_ripperdoc_done"];
    for fact in facts {
        if quests.GetFact(fact) < 1 {
            quests.SetFact(fact, 1);
        }
    }
    // A clean start isn't a Phantom Liberty story start. (It was switched on by
    // hand while testing; left on, it starts the PL story and its tutorials.)
    if quests.GetFact(n"ep1_standalone") != 0 {
        quests.SetFact(n"ep1_standalone", 0);
    }
}

// No quests in your journal on the server.
//
// Opening the world also wakes up the base game's story and side quests
// (Automatic Love, Ghost Town...). They're switched to inactive as soon as
// they appear, which takes them out of the journal, the on-screen tracker and
// the map. Their phone calls and texts are already refused. Only while
// connected; single player keeps its quests.
public class MpQuestSuppressor extends ScriptableSystem {
    private let m_listening: Bool;

    public static func Get() -> ref<MpQuestSuppressor> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpQuestSuppressor") as MpQuestSuppressor;
    }

    // Started by the launcher: quiet from the first moment in the world, not
    // only once connected.
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
        let network = GameInstance.GetNetworkWorldSystem();
        if IsDefined(network) && network.HasServerSession() {
            this.Start();
        }
    }

    private let m_sweepPending: Bool;
    private let m_seenQuests: array<Uint32>;
    private let m_seenCounts: array<Int32>;

    // Called on connecting: clears what's already there and keeps watching.
    public func Start() -> Void {
        let journal = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(journal) {
            return;
        }
        if !this.m_listening {
            journal.RegisterScriptCallback(this, n"OnMpJournalState", gameJournalListenerType.State);
            this.m_listening = true;
        }
        this.Sweep();
    }

    // The journal says a quest changed. Never answered on the spot: switching a
    // quest off inside this callback lets a quest that switches itself straight
    // back on bounce forever and freeze the game. A sweep a moment later instead.
    protected cb func OnMpJournalState(entryHash: Uint32, className: CName, notifyOption: JournalNotifyOption, changeType: JournalChangeType) -> Bool {
        if !Equals(className, n"gameJournalQuest") || !MpQuestsSilenced() || this.m_sweepPending {
            return false;
        }
        this.m_sweepPending = true;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(new MpQuestSweep(), 1.0, false);
        return false;
    }

    public func Sweep() -> Void {
        this.m_sweepPending = false;
        if !MpQuestsSilenced() {
            return;
        }
        let journal = GameInstance.GetJournalManager(this.GetGameInstance());
        if !IsDefined(journal) {
            return;
        }
        let context: JournalRequestContext;
        context.stateFilter.active = true;
        let quests: array<wref<JournalEntry>>;
        journal.GetQuests(context, quests);
        for quest in quests {
            let hash = Cast<Uint32>(journal.GetEntryHash(quest));
            // A quest the story keeps switching back on is left alone after a
            // few tries (it stays untracked); fighting it is what can freeze.
            if this.Bump(hash) <= 3 {
                journal.ChangeEntryStateByHash(hash, gameJournalEntryState.Inactive, JournalNotifyOption.DoNotNotify);
            }
        }
        journal.UntrackEntry();
    }

    private func Bump(hash: Uint32) -> Int32 {
        let i = 0;
        while i < ArraySize(this.m_seenQuests) {
            if this.m_seenQuests[i] == hash {
                this.m_seenCounts[i] += 1;
                return this.m_seenCounts[i];
            }
            i += 1;
        }
        ArrayPush(this.m_seenQuests, hash);
        ArrayPush(this.m_seenCounts, 1);
        return 1;
    }
}

public class MpQuestSweep extends DelayCallback {
    public func Call() -> Void {
        let suppressor = MpQuestSuppressor.Get();
        if IsDefined(suppressor) {
            suppressor.Sweep();
        }
    }
}
