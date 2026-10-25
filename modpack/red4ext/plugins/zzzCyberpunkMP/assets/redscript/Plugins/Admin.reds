module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Ink.*

// Admin tools. Type /admin in chat to open the panel (Ink/AdminPanelUI.reds).
// The server decides who's an admin (config/admins.json) and checks every
// action; for anyone else the request is refused.

public native class AdminServer extends ServerRpc {
    public static native func OpenPanel() -> Void;
    public static native func SetAdmin(character: String, admin: Bool) -> Void;
    public static native func Kick(character: String, reason: String) -> Void;
    public static native func Ban(character: String, reason: String) -> Void;
    public static native func Heal(character: String) -> Void;
    public static native func GoTo(character: String) -> Void;
    public static native func Bring(character: String) -> Void;
    public static native func TeleportSelf(x: Float, y: Float, z: Float) -> Void;
    public static native func AddPlace(name: String, x: Float, y: Float, z: Float) -> Void;
    public static native func RemovePlace(name: String) -> Void;
}

public class AdminClient extends ClientRpc {
    public func ShowPanel(payload: String) -> Void {
        let panel = MpAdminPanel.Get();
        if IsDefined(panel) {
            panel.OnData(payload);
        }
    }

    public func Teleport(x: Float, y: Float, z: Float) -> Void {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let facing: EulerAngles;
        GameInstance.GetTeleportationFacility(GetGameInstance()).Teleport(player, new Vector4(x, y, z, 1.0), facing);
    }

    public func Heal(note: String) -> Void {
        MpHealSelf();
        MpJobMessage(note);
    }

    public func Kicked(reason: String) -> Void {
        MpJobMessage(reason);
        GameInstance.GetNetworkWorldSystem().Disconnect();
    }
}

// Full health, and up off the floor if downed.
public func MpHealSelf() -> Void {
    let player = GetPlayer(GetGameInstance());
    if !IsDefined(player) {
        return;
    }
    GameInstance.GetStatPoolsSystem(player.GetGame())
        .RequestSettingStatPoolValue(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, 100.0, player, true);
    StatusEffectHelper.RemoveStatusEffect(player, t"BaseStatusEffect.Defeated");
    StatusEffectHelper.RemoveStatusEffect(player, t"GameplayRestriction.BlockAllMenu");
}

// Waypoint the player set on their map, if any.
public func MpMapWaypoint(out position: Vector4) -> Bool {
    let mappins: array<ref<IMappin>>;
    GameInstance.GetMappinSystem(GetGameInstance()).GetMappins(gamemappinsMappinTargetType.Map, mappins);
    for mappin in mappins {
        if IsDefined(mappin) && Equals(mappin.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
            position = mappin.GetWorldPosition();
            return true;
        }
    }
    return false;
}

// Teleport to the map waypoint, finding the ground under it.
public func MpTeleportToWaypoint() -> Void {
    let target: Vector4;
    if !MpMapWaypoint(target) {
        MpJobMessage("Set a waypoint on your map first.");
        return;
    }
    let navigation = GameInstance.GetNavigationSystem(GetGameInstance());
    let offsets: array<Float> = [0.0, 30.0, 60.0, 120.0, -30.0];
    for offset in offsets {
        let result = navigation.FindPointInSphereOnlyHumanNavmesh(new Vector4(target.X, target.Y, target.Z + offset, 1.0), 40.0, NavGenAgentSize.Human, false);
        if Equals(result.status, worldNavigationRequestStatus.OK) && !Vector4.IsZero(result.point) {
            AdminServer.TeleportSelf(result.point.X, result.point.Y, result.point.Z + 0.5);
            return;
        }
    }
    // Nothing loaded there yet: arrive high and fall into the streamed ground.
    AdminServer.TeleportSelf(target.X, target.Y, target.Z + 2.0);
}
