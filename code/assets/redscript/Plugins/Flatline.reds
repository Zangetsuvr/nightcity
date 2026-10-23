module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Ink.*

// No death screen on the server.
//
// The game's death screen only offers to reload a save, which drops you off the
// server. While connected the player is kept alive at the last moment instead
// (the game's own "can't die" mode, the one cutscenes use). When health hits
// the bottom you go down: you can't move, fight or drive, only chat, and
// Trauma Team is called for you (CharacterSystem/Medical.cs). A medic who
// reaches you, or an admin, gets you up where you are. After the wait (3
// minutes by default) you can choose the hospital instead: press F twice.

public native class MedicalServer extends ServerRpc {
    public static native func Downed(x: Float, y: Float, z: Float) -> Void;
    public static native func GoToHospital() -> Void;
}

public class MedicalClient extends ClientRpc {
    public func SetDowned(seconds: Int32) -> Void {
        let flatline = MpFlatline.Get();
        if IsDefined(flatline) {
            flatline.StartWait(seconds);
        }
    }

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
    private let m_answered: Bool;
    private let m_left: Int32;
    private let m_hospitalPresses: Int32;
    private let m_listener: ref<MpFlatlineListener>;
    private let m_generation: Int32;
    private let m_canvas: ref<inkCanvas>;

    public static func Get() -> ref<MpFlatline> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpFlatline") as MpFlatline;
    }

    public func IsDown() -> Bool {
        return this.m_down;
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
    }

    // On disconnecting: single player is the game's own again.
    public func Disarm() -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if IsDefined(player) {
            if this.m_down {
                this.Restrict(player, false);
            }
            GameInstance.GetGodModeSystem(this.GetGameInstance()).RemoveGodMode(player.GetEntityID(), gameGodModeType.Immortal, n"CyberpunkMP");
            if IsDefined(this.m_listener) {
                GameInstance.GetStatPoolsSystem(this.GetGameInstance())
                    .RequestUnregisteringListener(Cast<StatsObjectID>(player.GetEntityID()), gamedataStatPoolType.Health, this.m_listener);
            }
        }
        this.m_listener = null;
        this.m_armed = false;
        this.m_down = false;
        this.HideHud();
    }

    public func Down() -> Void {
        if !this.m_armed || this.m_down {
            return;
        }
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        this.m_down = true;
        this.m_answered = false;
        this.m_left = 180;
        this.m_hospitalPresses = 0;
        this.m_generation += 1;
        if VehicleComponent.IsMountedToVehicle(this.GetGameInstance(), player) {
            MpExitVehicle(player);
        }
        this.Restrict(player, true);
        player.RegisterInputListener(this, n"Choice1");
        let p = player.GetWorldPosition();
        MedicalServer.Downed(p.X, p.Y, p.Z);
        this.ScheduleTick();
        this.DrawHud();
    }

    // The server says how long until the hospital is an option.
    public func StartWait(seconds: Int32) -> Void {
        if !this.m_down {
            return;
        }
        this.m_answered = true;
        this.m_left = seconds;
        this.DrawHud();
    }

    private func ScheduleTick() -> Void {
        let tick = new MpFlatlineTick();
        tick.generation = this.m_generation;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(tick, 1.0, false);
    }

    public func Tick(generation: Int32) -> Void {
        if !this.m_down || generation != this.m_generation {
            return;
        }
        if this.m_left > 0 {
            this.m_left -= 1;
        }
        // A server without this feature never answers: don't leave them down.
        if !this.m_answered && this.m_left <= 172 {
            let player = GetPlayer(this.GetGameInstance());
            if IsDefined(player) {
                this.WakeUp(player.GetWorldPosition(), "You pulled through.");
            }
            return;
        }
        this.DrawHud();
        this.ScheduleTick();
    }

    protected cb func OnAction(action: ListenerAction, consumer: ListenerActionConsumer) -> Bool {
        if !this.m_down || this.m_left > 0 {
            return false;
        }
        if Equals(ListenerAction.GetName(action), n"Choice1") && Equals(ListenerAction.GetType(action), gameinputActionType.BUTTON_PRESSED) {
            this.m_hospitalPresses += 1;
            if this.m_hospitalPresses >= 2 {
                this.m_hospitalPresses = 0;
                MedicalServer.GoToHospital();
            } else {
                this.DrawHud();
            }
            return true;
        }
        return false;
    }

    public func WakeUp(position: Vector4, note: String) -> Void {
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let wasDown = this.m_down;
        this.m_down = false;
        this.m_generation += 1;
        player.UnregisterInputListener(this, n"Choice1");
        if wasDown {
            this.Restrict(player, false);
        }
        this.HideHud();
        // Only moved if it's somewhere else (the hospital); a medic revives in place.
        if Vector4.Distance(player.GetWorldPosition(), position) > 5.0 {
            if VehicleComponent.IsMountedToVehicle(this.GetGameInstance(), player) {
                let later = new MpFlatlineTeleport();
                later.position = position;
                GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(later, 0.5, false);
                MpExitVehicle(player);
            } else {
                MpFlatlineMove(player, position);
            }
            MpClearHeat();
        }
        StatusEffectHelper.RemoveStatusEffectsWithTag(player, n"Debuff");
        MpHealSelf();
        MpJobMessage(note);
        MpSaveAfter(4.0);
    }

    // Down: no moving, fighting, driving or menus. Chat still works.
    private func Restrict(player: ref<PlayerPuppet>, on: Bool) -> Void {
        let effects: array<TweakDBID> = [t"GameplayRestriction.NoMovement", t"GameplayRestriction.NoWeapons", t"GameplayRestriction.NoJump",
            t"GameplayRestriction.NoWorldInteractions", t"GameplayRestriction.NoRadialMenus", t"GameplayRestriction.BlockFastTravel",
            t"GameplayRestriction.NoScanning", t"GameplayRestriction.ForceCrouch"];
        for effect in effects {
            if on {
                StatusEffectHelper.ApplyStatusEffect(player, effect);
            } else {
                StatusEffectHelper.RemoveStatusEffect(player, effect);
            }
        }
    }

    // ------------------------------------------------------------- on screen

    private func HideHud() -> Void {
        if IsDefined(this.m_canvas) {
            let parent = this.m_canvas.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.m_canvas);
            }
            this.m_canvas = null;
        }
    }

    private func DrawHud() -> Void {
        let controller = GameInstance.GetNetworkWorldSystem().GetAppearanceSystem().m_controller;
        if !IsDefined(controller) {
            return;
        }
        let root = controller.GetRootCompoundWidget();
        if !IsDefined(root) {
            return;
        }
        if !IsDefined(this.m_canvas) {
            let canvas = new inkCanvas();
            canvas.SetName(n"mp_downed");
            canvas.SetAnchor(inkEAnchor.TopLeft);
            canvas.SetAnchorPoint(new Vector2(0.0, 0.0));
            canvas.SetSize(new Vector2(1920.0, 1080.0));
            canvas.SetInteractive(false);
            canvas.Reparent(root);
            this.m_canvas = canvas;
        }
        let size = root.GetSize();
        let scale = size.X > 1.0 ? size.X / 1920.0 : 2.0;
        let offsetY = size.Y > 1.0 ? (size.Y - 1080.0 * scale) / 2.0 : 0.0;
        this.m_canvas.SetMargin(new inkMargin(0.0, offsetY, 0.0, 0.0));
        this.m_canvas.SetRenderTransformPivot(new Vector2(0.0, 0.0));
        this.m_canvas.SetScale(new Vector2(scale, scale));
        this.m_canvas.RemoveAllChildren();

        let c = this.m_canvas;
        let x = 660.0;
        let y = 300.0;
        MpJbRect(c, x, y, 600.0, 190.0, MpJbPlate(), 0.85);
        MpJbRect(c, x, y, 600.0, 3.0, MpJbRed(), 1.0);
        MpJbText(c, x + 30.0, y + 20.0, "FLATLINED", 52, n"Bold", MpJbRed());
        MpJbText(c, x + 30.0, y + 90.0, "Trauma Team has been called. Hang on.", 24, n"Regular", MpJbInk());
        if this.m_left > 0 {
            let minutes = this.m_left / 60;
            let seconds = this.m_left % 60;
            let clock = IntToString(minutes) + ":" + (seconds < 10 ? "0" : "") + IntToString(seconds);
            MpJbText(c, x + 30.0, y + 130.0, "Hospital available in " + clock, 24, n"Medium", MpJbInkDim());
        } else {
            let hint = this.m_hospitalPresses > 0 ? "Press F again to go to the hospital" : "Press F twice to go to the hospital";
            MpJbText(c, x + 30.0, y + 130.0, hint, 26, n"Bold", MpJbGold());
        }
    }
}

public class MpFlatlineTick extends DelayCallback {
    public let generation: Int32;

    public func Call() -> Void {
        let flatline = MpFlatline.Get();
        if IsDefined(flatline) {
            flatline.Tick(this.generation);
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
