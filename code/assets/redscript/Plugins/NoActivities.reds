module CyberpunkMP.Plugins

import CyberpunkMP.*

// No gigs, side jobs, cyberpsycho sightings or NCPD hustles on the server.
//
// Their markers are hidden everywhere (world map, minimap, in the world) and
// story/fixer texts don't pop up, so nothing points players at them. Story and
// fixer calls are already blocked (Quests.reds). Disconnected, single player is
// untouched.

public func MpHiddenActivity(variant: gamedataMappinVariant) -> Bool {
    if !MpWorldKeepsRunning() {
        return false;
    }
    switch variant {
        // Gigs and fixers
        case gamedataMappinVariant.FixerVariant:
        case gamedataMappinVariant.BountyHuntVariant:
        case gamedataMappinVariant.ConvoyVariant:
        case gamedataMappinVariant.CourierVariant:
        case gamedataMappinVariant.Zzz09_CourierSandboxActivityVariant:
        case gamedataMappinVariant.RetrievingVariant:
        case gamedataMappinVariant.SabotageVariant:
        case gamedataMappinVariant.ThieveryVariant:
        case gamedataMappinVariant.ClientInDistressVariant:
        // Side jobs and undiscovered "?"
        case gamedataMappinVariant.QuestGiverVariant:
        case gamedataMappinVariant.DefaultQuestVariant:
        case gamedataMappinVariant.ExclamationMarkVariant:
        case gamedataMappinVariant.QuestionMarkVariant:
        // Cyberpsycho sightings
        case gamedataMappinVariant.HuntForPsychoVariant:
        // NCPD scanner hustles and world encounters
        case gamedataMappinVariant.Zzz06_NCPDGigVariant:
        case gamedataMappinVariant.GangWatchVariant:
        case gamedataMappinVariant.OutpostVariant:
        case gamedataMappinVariant.MinorActivityVariant:
        case gamedataMappinVariant.Zzz12_WorldEncounterVariant:
        case gamedataMappinVariant.SOSsignalVariant:
        case gamedataMappinVariant.SmugglersDenVariant:
        case gamedataMappinVariant.Zzz11_RoadBlockadeVariant:
            return true;
    }
    return false;
}

@wrapMethod(WorldMapMenuGameController)
public func CreateMappinUIProfile(mappin: wref<IMappin>, mappinVariant: gamedataMappinVariant, customData: ref<MappinControllerCustomData>) -> MappinUIProfile {
    if MpHiddenActivity(mappinVariant) {
        return MappinUIProfile.None();
    }
    return wrappedMethod(mappin, mappinVariant, customData);
}

// Texts from fixers and story characters (the way gigs and sightings start).
@wrapMethod(NewHudPhoneGameController)
public final func PushSMSNotification(msgEntry: wref<JournalPhoneMessage>, opt action: ref<GenericNotificationBaseAction>) -> Void {
    if MpWorldKeepsRunning() {
        return;
    }
    wrappedMethod(msgEntry, action);
}
