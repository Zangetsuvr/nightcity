module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

// The job board's link to the server, and the marker for the contract you're on.
// The board itself (what you see when you press the job key) is in
// Ink/JobBoardUI.reds.

public native class JobBoardServer extends ServerRpc {
    public static native func OpenBoard() -> Void;
    public static native func GoOnDuty(job: String) -> Void;
    public static native func GoOffDuty() -> Void;
    public static native func OpenContracts() -> Void;
    public static native func AcceptContract(id: Uint32) -> Void;
    public static native func CancelContract() -> Void;
    public static native func CallService(service: String) -> Void;
    // Where the marker really is, once the game has found solid ground near it.
    public static native func ConfirmTarget(x: Float, y: Float, z: Float) -> Void;
    // Nowhere to stand near the marker (water, inside a building): pick another spot.
    public static native func ReportUnreachable() -> Void;
}

public class JobBoardClient extends ClientRpc {
    public func ShowBoard(payload: String) -> Void {
        let board = MpJobBoard.Get();
        if IsDefined(board) {
            board.OnBoardData(payload);
        }
    }

    public func ShowContracts(payload: String) -> Void {
        let board = MpJobBoard.Get();
        if IsDefined(board) {
            board.OnContractsData(payload);
        }
    }

    public func SetObjective(x: Float, y: Float, z: Float, text: String, spawnVehicle: String) -> Void {
        let objective = MpJobObjective.Get();
        if IsDefined(objective) {
            objective.Set(new Vector4(x, y, z, 1.0), text, spawnVehicle);
        }
    }

    public func ClearObjective(message: String) -> Void {
        let objective = MpJobObjective.Get();
        if IsDefined(objective) {
            objective.Clear(message);
        }
    }

    public func RepairMyVehicle(note: String) -> Void {
        let player = GetPlayer(GetGameInstance());
        if !IsDefined(player) {
            return;
        }
        let vehicle = GetMountedVehicle(player);
        if !IsDefined(vehicle) {
            MpJobMessage("The mechanic's done, but you weren't in your car. Get in and call again if it still needs work.");
            return;
        }
        vehicle.QueueEvent(new VehicleRepairEvent());
        vehicle.DestructionResetGrid();
        MpJobMessage(note);
    }
}

// A short message in the middle of the screen.
public func MpJobMessage(text: String) -> Void {
    if StrLen(text) == 0 {
        return;
    }
    let message: SimpleScreenMessage;
    message.isShown = true;
    message.duration = 6.0;
    message.message = text;
    let game = GetGameInstance();
    GameInstance.GetBlackboardSystem(game).Get(GetAllBlackboardDefs().UI_Notifications)
        .SetVariant(GetAllBlackboardDefs().UI_Notifications.OnscreenMessage, ToVariant(message), true);
}

// The marker for the current contract stage. The server only knows roughly
// where it is (no height, maybe in a wall); once the player gets close, the
// game finds the nearest place a person can stand, moves the marker there and
// tells the server. If there's nowhere, the server picks another spot.
public class MpJobObjective extends ScriptableSystem {
    private let m_active: Bool;
    private let m_mappin: NewMappinID;
    private let m_hasMappin: Bool;
    private let m_target: Vector4;
    private let m_confirmed: Bool;
    private let m_reportedUnreachable: Bool;
    private let m_vehicleRecord: String;
    private let m_vehicle: EntityID;
    private let m_hasVehicle: Bool;
    private let m_generation: Int32;

    public static func Get() -> ref<MpJobObjective> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpJobObjective") as MpJobObjective;
    }

    public func Set(target: Vector4, text: String, spawnVehicle: String) -> Void {
        this.RemoveMappin();
        this.m_active = true;
        this.m_target = target;
        this.m_confirmed = false;
        this.m_reportedUnreachable = false;
        this.m_vehicleRecord = spawnVehicle;
        this.AddMappin(target);
        MpJobMessage(text);
        this.m_generation += 1;
        this.SchedulePoll();
    }

    public func Clear(message: String) -> Void {
        this.m_active = false;
        this.m_generation += 1;
        this.RemoveMappin();
        this.RemoveVehicle();
        MpJobMessage(message);
    }

    private func AddMappin(position: Vector4) -> Void {
        let data: MappinData;
        data.mappinType = t"Mappins.QuestStaticMappinDefinition";
        data.variant = gamedataMappinVariant.CPO_PingGoHereVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        this.m_mappin = GameInstance.GetMappinSystem(this.GetGameInstance()).RegisterMappin(data, position);
        this.m_hasMappin = true;
    }

    private func RemoveMappin() -> Void {
        if this.m_hasMappin {
            GameInstance.GetMappinSystem(this.GetGameInstance()).UnregisterMappin(this.m_mappin);
            this.m_hasMappin = false;
        }
    }

    // A car the tow job spawned stays while you're driving it, and goes once you aren't.
    private func RemoveVehicle() -> Void {
        if !this.m_hasVehicle {
            return;
        }
        let player = GetPlayer(this.GetGameInstance());
        let mounted = IsDefined(player) ? GetMountedVehicle(player) : null;
        if IsDefined(mounted) && mounted.GetEntityID() == this.m_vehicle {
            return;
        }
        GameInstance.GetDynamicEntitySystem().DeleteEntity(this.m_vehicle);
        this.m_hasVehicle = false;
    }

    private func SchedulePoll() -> Void {
        let poll = new MpJobObjectivePoll();
        poll.generation = this.m_generation;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(poll, 1.5, false);
    }

    public func Poll(generation: Int32) -> Void {
        if !this.m_active || generation != this.m_generation {
            return;
        }
        let player = GetPlayer(this.GetGameInstance());
        if !IsDefined(player) {
            this.SchedulePoll();
            return;
        }

        if !this.m_confirmed {
            let here = player.GetWorldPosition();
            let dx = here.X - this.m_target.X;
            let dy = here.Y - this.m_target.Y;
            let distance = SqrtF(dx * dx + dy * dy);
            if distance < 220.0 {
                let ground: Vector4;
                if this.FindGround(here.Z, ground) {
                    this.m_confirmed = true;
                    this.m_target = ground;
                    GameInstance.GetMappinSystem(this.GetGameInstance()).SetMappinPosition(this.m_mappin, ground);
                    JobBoardServer.ConfirmTarget(ground.X, ground.Y, ground.Z);
                    if StrLen(this.m_vehicleRecord) > 0 {
                        this.SpawnVehicle(ground);
                    }
                } else {
                    if distance < 120.0 && !this.m_reportedUnreachable {
                        this.m_reportedUnreachable = true;
                        JobBoardServer.ReportUnreachable();
                    }
                }
            }
        }
        this.SchedulePoll();
    }

    // The nearest place a person can stand around the marker, searched at a
    // few heights around the player's own.
    private func FindGround(playerZ: Float, out ground: Vector4) -> Bool {
        let navigation = GameInstance.GetNavigationSystem(this.GetGameInstance());
        let offsets: array<Float> = [0.0, 12.0, -12.0, 30.0, -30.0, 60.0, -60.0];
        for offset in offsets {
            let center = new Vector4(this.m_target.X, this.m_target.Y, playerZ + offset, 1.0);
            let result = navigation.FindPointInSphereOnlyHumanNavmesh(center, 60.0, NavGenAgentSize.Human, false);
            if Equals(result.status, worldNavigationRequestStatus.OK) && !Vector4.IsZero(result.point) {
                ground = result.point;
                return true;
            }
        }
        return false;
    }

    private func SpawnVehicle(position: Vector4) -> Void {
        let record = TDBID.Create(this.m_vehicleRecord);
        if !IsDefined(TweakDBInterface.GetVehicleRecord(record)) {
            record = t"Vehicle.v_standard2_archer_hella_player";
        }
        let spec = new DynamicEntitySpec();
        spec.recordID = record;
        spec.position = new Vector4(position.X, position.Y, position.Z + 0.5, 1.0);
        spec.orientation = EulerAngles.ToQuat(new EulerAngles(0.0, 0.0, RandRangeF(0.0, 360.0)));
        spec.alwaysSpawned = true;
        spec.persistState = false;
        spec.persistSpawn = false;
        spec.tags = [n"CyberpunkMP.JobVehicle"];
        this.RemoveVehicle();
        this.m_vehicle = GameInstance.GetDynamicEntitySystem().CreateEntity(spec);
        this.m_hasVehicle = true;
    }
}

public class MpJobObjectivePoll extends DelayCallback {
    public let generation: Int32;

    public func Call() -> Void {
        let objective = MpJobObjective.Get();
        if IsDefined(objective) {
            objective.Poll(this.generation);
        }
    }
}
