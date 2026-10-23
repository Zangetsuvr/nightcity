module CyberpunkMP.World

import Codeware.*
import CyberpunkMP.*
import CyberpunkMP.Plugins.*

public native class NetworkWorldSystem extends IGameSystem {
    public native func Connect() -> Void;
    public native func Disconnect() -> Void;

    // Character names (see Plugins/CharacterName.reds).
    public native func HasServerSession() -> Bool;
    public native func IsConnected() -> Bool;
    public native func TakeAutoStart() -> Bool;
    public native func GetAccountCharacterCount() -> Int32;
    public native func RequestNameCheck(name: String) -> Void;
    public native func RequestNameReserve(name: String) -> Void;
    public native func GetNameStatus() -> Int32;
    public native func GetNameStatusMessage() -> String;
    public native func GetNameStatusName() -> String;
    public native func SetCharacterName(name: String) -> Void;
    public native func GetCharacterName() -> String;
    public native func SetPendingCharacterName(name: String) -> Void;
    public native func TakePendingCharacterName() -> String;
    public native func EncodeName(name: String) -> array<Uint8>;
    public native func DecodeName(bytes: array<Uint8>) -> String;
    public native func GetEntityIdByServerId(serverId: Uint64) -> EntityID;
    public native func GetAppearanceSystem() -> ref<AppearanceSystem>;
    public native func GetChatSystem() -> ref<ChatSystem>;
    public native func GetInterpolationSystem() -> ref<InterpolationSystem>;
    public native func GetVehicleSystem() -> ref<VehicleSystem>;

    public func OnConnected() -> Void {
        // let evt: ref<ConnectedToServer>;
        // evt.m_connected = true;
        // GameInstance.GetUISystem(GetGameInstance()).QueueEvent(evt);
        
        let blackboardSystem: ref<BlackboardSystem> = GameInstance.GetBlackboardSystem(GetGameInstance());
        let blackboard: ref<IBlackboard> = blackboardSystem.Get(GetAllBlackboardDefs().UIGameData);
        blackboard.SetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer, true, true);

        // Story calls stay closed while on the server (see Plugins/Quests.reds).
        MpSilenceStoryHolocalls();

        // Vendors, ripperdocs and the rest of the open world (Plugins/Quests.reds).
        MpOpenWorld();

        // Get this character's saved balance and progress from the server
        // (and, for a brand-new character, be moved to the start point).
        // Not right away: the server's list of calls arrives in the same batch
        // as "you're in" but can be read just after it, and a call made before
        // that list is read goes nowhere.
        GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(new MpRequestCharacterSync(), 1.0, false);

        // Keep the local save current while on the server (Plugins/Saving.reds).
        let keeper = MpSaveKeeper.Get();
        if IsDefined(keeper) {
            keeper.Start();
        }
    }

    public func OnDisconnected(reason: Uint32) -> Void {
        // let evt: ref<ConnectedToServer>;
        // evt.m_connected = true;
        // GameInstance.GetUISystem(GetGameInstance()).QueueEvent(evt);
        
        let blackboardSystem: ref<BlackboardSystem> = GameInstance.GetBlackboardSystem(GetGameInstance());
        let blackboard: ref<IBlackboard> = blackboardSystem.Get(GetAllBlackboardDefs().UIGameData);
        blackboard.SetBool(GetAllBlackboardDefs().UIGameData.UIMultiplayerConnectedToServer, false, true);
    }

    public func CreatePuppet(position: Vector4, rotation: Quaternion, isMale: Bool) -> EntityID {
        let npcSpec = new DynamicEntitySpec();

        if isMale {
            npcSpec.recordID = t"Character.MaMuppet";
        } else {
            npcSpec.recordID = t"Character.WaMuppet";
            // npcSpec.recordID = t"Character.Panam";
        }
        npcSpec.alwaysSpawned = true;
        npcSpec.position = position;
        npcSpec.orientation = rotation;
        npcSpec.persistState = false;
        npcSpec.persistSpawn = false;
        npcSpec.tags = [n"CyberpunkMP.Puppet"];


        return GameInstance.GetDynamicEntitySystem().CreateEntity(npcSpec);
    }

    public func DeletePuppet(entityId: EntityID) {
        GameInstance.GetDynamicEntitySystem().DeleteEntity(entityId);
    }
}

@addMethod(GameInstance)
public static native func GetNetworkWorldSystem() -> ref<NetworkWorldSystem>
public class MpRequestCharacterSync extends DelayCallback {
    public func Call() -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if IsDefined(world) && world.IsConnected() {
            // Lifepath first: a new character's starter kit is handed out before
            // the sync moves them to the start point.
            let player = GetPlayer(GetGameInstance());
            if IsDefined(player) {
                let lifepath = PlayerDevelopmentSystem.GetInstance(player).GetLifePath(player);
                CharacterServer.ClaimStarterKit(EnumInt(lifepath));
            }
            CharacterServer.RequestSync();
        }
    }
}
