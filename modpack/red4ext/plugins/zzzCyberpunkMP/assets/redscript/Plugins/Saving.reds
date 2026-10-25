module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// Keeps the local save up to date while on the server.
//
// The launcher starts the game from the newest save, and position, inventory and
// gear all live in that save. Without regular saves, anything that happened since
// the last one (a starter kit, a new jacket, a drive across town) was gone the
// next time you joined. So while connected the game saves:
//   - every minute,
//   - a few seconds after the server hands over a starter kit or moves you,
//   - when the pause menu opens (which is how people usually leave).
// Money doesn't depend on any of this: the server keeps it.

public class MpSaveKeeper extends ScriptableSystem {
    private let m_running: Bool;

    public static func Get() -> ref<MpSaveKeeper> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpSaveKeeper") as MpSaveKeeper;
    }

    // Called on connecting; starts the once-a-minute save if it isn't running.
    public func Start() -> Void {
        if this.m_running {
            return;
        }
        this.m_running = true;
        this.ScheduleNext();
    }

    public func ScheduleNext() -> Void {
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(new MpPeriodicSave(), 60.0, false);
    }

    public func Tick() -> Void {
        if !MpWorldKeepsRunning() {
            this.m_running = false;
            return;
        }
        MpSaveNow();
        this.ScheduleNext();
    }
}

public class MpPeriodicSave extends DelayCallback {
    public func Call() -> Void {
        let keeper = MpSaveKeeper.Get();
        if IsDefined(keeper) {
            keeper.Tick();
        }
    }
}

public class MpSaveSoon extends DelayCallback {
    public func Call() -> Void {
        if MpWorldKeepsRunning() {
            MpSaveNow();
        }
    }
}

// Save in a few seconds (once what just happened has settled in).
public func MpSaveAfter(seconds: Float) -> Void {
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(new MpSaveSoon(), seconds, false);
}

public func MpSaveNow() -> Void {
    GameInstance.GetAutoSaveSystem(GetGameInstance()).RequestForcedCheckpoint();
}
