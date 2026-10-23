module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// Windows pointer stuck on screen.
//
// Started from the launcher, the game window sometimes opens without Windows
// handing it the mouse, so the system pointer stays visible over the game until
// the player switches window mode and back. This does that switch for them,
// once, a moment after they first arrive in the world: their window mode is
// changed to another one and straight back to their own.

// Lives for the whole time the game is open, so the fix runs once per launch.
public class MpCursorFixState extends ScriptableService {
    public let done: Bool;
}

public func MpCursorFixService() -> ref<MpCursorFixState> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"CyberpunkMP.Plugins.MpCursorFixState") as MpCursorFixState;
}

public class MpCursorFix extends ScriptableSystem {
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(world) || !world.HasServerSession() {
            return;
        }
        let state = MpCursorFixService();
        if IsDefined(state) {
            if state.done {
                return;
            }
            state.done = true;
        }
        let step = new MpCursorFixStep();
        step.away = true;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(step, 2.0, false);
    }
}

public class MpCursorFixStep extends DelayCallback {
    public let away: Bool;
    public let original: Int32;

    public func Call() -> Void {
        let settings = GameInstance.GetSettingsSystem(GetGameInstance());
        if !IsDefined(settings) || !settings.HasVar(n"/video/display", n"WindowMode") {
            return;
        }
        let mode = settings.GetVar(n"/video/display", n"WindowMode");
        if this.away {
            let current = MpModeIndex(mode);
            let count = MpModeCount(mode);
            if current < 0 || count < 2 {
                return;
            }
            MpSetModeIndex(mode, (current + 1) % count);
            settings.ConfirmChanges();
            let back = new MpCursorFixStep();
            back.away = false;
            back.original = current;
            GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(back, 0.6, false);
        } else {
            MpSetModeIndex(mode, this.original);
            settings.ConfirmChanges();
        }
    }
}

// The window mode setting is a list; which kind depends on the game version.
public func MpModeIndex(v: ref<ConfigVar>) -> Int32 {
    let n = v as ConfigVarListName;
    if IsDefined(n) { return n.GetIndex(); }
    let s = v as ConfigVarListString;
    if IsDefined(s) { return s.GetIndex(); }
    let i = v as ConfigVarListInt;
    if IsDefined(i) { return i.GetIndex(); }
    return -1;
}

public func MpModeCount(v: ref<ConfigVar>) -> Int32 {
    let n = v as ConfigVarListName;
    if IsDefined(n) { let values = n.GetValues(); return ArraySize(values); }
    let s = v as ConfigVarListString;
    if IsDefined(s) { let values = s.GetValues(); return ArraySize(values); }
    let i = v as ConfigVarListInt;
    if IsDefined(i) { let values = i.GetValues(); return ArraySize(values); }
    return 0;
}

public func MpSetModeIndex(v: ref<ConfigVar>, index: Int32) -> Void {
    let n = v as ConfigVarListName;
    if IsDefined(n) { n.SetIndex(index); return; }
    let s = v as ConfigVarListString;
    if IsDefined(s) { s.SetIndex(index); return; }
    let i = v as ConfigVarListInt;
    if IsDefined(i) { i.SetIndex(index); }
}
