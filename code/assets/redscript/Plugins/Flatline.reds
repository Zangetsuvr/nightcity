module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

// No death screen on the server.
//
// The game's death screen only offers to reload a save, which drops you off the
// server. While connected the player is kept alive at the last moment instead
// (the game's own "can't die" mode, the one cutscenes use). When health hits
// the bottom you're "flatlined": the server picks the nearest hospital and
// takes the trauma bill (CharacterSystem/Medical.cs), and you wake up there,
// healed, with the police off your back.

public native class MedicalServer extends ServerRpc {
    public static native func Flatlined(x: Float, y: Float, z: Float) -> Void;
}

public class MedicalClient extends ClientRpc {
    public func Revive(x: Float, y: Float, z: Float, note: String) -> Void {
        let flatline = MpFlatline.Get();
        if IsDefined(flatline) {
            flatline.WakeUp(new Vector4(x, y, z, 1.0), note);
        }
    }
}

public class MpFlatlineListener extends ScriptStatPoolsListener {
    public func OnStatPoolValueChanged(oldValue: Float, newValue: Float, percToPoints: Float) -> Void {
        // Values are percentages. "Can't die" stops just above zero.
        if newValue <= 1.0 && oldValue > newValue {
            let flatline = MpFlatline.Get();
            if IsDefined(flatline) {
                flatline.Down();
            }
        }
    }
}

public class MpFlatline extends ScriptableSystem {
    private let m_armed: Bool;
    private let m_down: Bool;
    private let m_listener: ref<MpFlatlineListener>;
    private let m_generation: Int32;

    public static func Get() -> ref<MpFlatline> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpFlatline") as MpFlatline;
    }

    // On connecting: can't die, and watch health.
    public func Arm() -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        GameInstance.GetGodModeSystem(this.GetGameInstance()).AddGodMode(player.GetEntityID(), gameGodModeType.Immortal, n"CyberpunkMP");
        if !IsDefined(this.m_listener) {
            this.m_listener = new MpFlatlineListener();
            GameInstance.GetStatPoolsSystem(this.GetGameInstance())
                .RequestRegisteringListener(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, this.m_listener);
        }
        this.m_armed = true;
        this.m_down = false;
    }

    // On disconnecting: single player is the game's own again.
    public func Disarm() -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            GameInstance.GetGodModeSystem(this.GetGameInstance()).RemoveGodMode(player.GetEntityID(), gameGodModeType.Immortal, n"CyberpunkMP");
            if IsDefined(this.m_listener) {
                GameInstance.GetStatPoolsSystem(this.GetGameInstance())
                    .RequestUnregisteringListener(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, this.m_listener);
            }
        }
        this.m_listener = null;
        this.m_armed = false;
        this.m_down = false;
    }

    public func Down() -> Void {
        if !this.m_armed || this.m_down {
            return;
        }
        this.m_down = true;
        this.m_generation += 1;
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        MpJobMessage("FLATLINED");
        let p = player.GetWorldPosition();
        MedicalServer.Flatlined(p.X, p.Y, p.Z);
        // If the server doesn't answer, get up where you are.
        let fallback = new MpFlatlineFallback();
        fallback.generation = this.m_generation;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(fallback, 6.0, false);
    }

    public func Fallback(generation: Int32) -> Void {
        if this.m_down && generation == this.m_generation {
            let player = GetPlayer(this.GetGameInstance());
            if IsDefined(player) {
                this.WakeUp(player.GetWorldPosition(), "You pulled through.");
            }
        }
    }

    public func WakeUp(position: Vector4, note: String) -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        this.m_down = false;
        this.m_generation += 1;
        if VehicleComponent.IsMountedToVehicle(this.GetGameInstance(), player) {
            let unmount = new MpFlatlineTeleport();
            unmount.position = position;
            GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(unmount, 0.5, false);
            MpExitVehicle(player);
        } else {
            MpFlatlineMove(player, position);
        }
        StatusEffectHelper.RemoveStatusEffectsWithTag(player, n"Debuff");
        MpHealSelf();
        MpClearHeat();
        MpJobMessage(note);
        MpSaveAfter(4.0);
    }
}

public class MpFlatlineFallback extends DelayCallback {
    public let generation: Int32;

    public func Call() -> Void {
        let flatline = MpFlatline.Get();
        if IsDefined(flatline) {
            flatline.Fallback(this.generation);
        }
    }
}

public class MpFlatlineTeleport extends DelayCallback {
    public let position: Vector4;

    public func Call() -> Void {
        let player = GetPlayer(GetGameInstance());
        if IsDefined(player) {
            MpFlatlineMove(player, this.position);
        }
    }
}

public func MpFlatlineMove(player: ref<PlayerPuppet>, position: Vector4) -> Void {
    let facing: EulerAngles;
    GameInstance.GetTeleportationFacility(player.GetGame()).Teleport(player, position, facing);
}

public func MpExitVehicle(player: ref<PlayerPuppet>) -> Void {
    let mounting = GameInstance.GetMountingFacility(player.GetGame());
    let unmount = new UnmountingRequest();
    unmount.lowLevelMountingInfo = mounting.GetMountingInfoSingleWithObjects(player);
    let data = new MountEventData();
    data.isInstant = true;
    unmount.mountData = data;
    mounting.Unmount(unmount);
}

// Police lose interest in someone who was just flatlined.
public func MpClearHeat() -> Void {
    let prevention = GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"PreventionSystem") as PreventionSystem;
    if IsDefined(prevention) {
        prevention.MpClearHeat();
    }
}

@addMethod(PreventionSystem)
public func MpClearHeat() -> Void {
    this.ChangeHeatStage(EPreventionHeatStage.Heat_0, "CyberpunkMP flatline");
}
