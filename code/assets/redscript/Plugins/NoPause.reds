module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// The world keeps going on a server.
//
// Ported from the ofmiceandcam98-eng/CyberpunkMP fork (PauseMenu.reds and
// TimeDilation.reds), which is itself based on Tilted Phoques' CyberpunkMP.
//
// Pausing or slowing time only happens on one player's machine: the server and
// everyone else carry on, so that player comes back out of sync with the world.
// While connected:
//   - the pause menu opens as usual, but the world keeps running behind it,
//   - the weapon wheel, phone, emote wheel, Sandevistan, deflect and the other
//     slow-motion effects don't slow anything,
//   - skipping time (waiting or sleeping) doesn't move the clock.
// Disconnected, all of it works exactly as in single player again.

// Are we on a server right now? Asked every time, never cached.
public func MpWorldKeepsRunning() -> Bool {
    let network = GameInstance.GetNetworkWorldSystem();
    return IsDefined(network) && network.IsConnected();
}

// ---------------------------------------------------------------- pause menu

// Lifts the pause a moment after the pause menu opens. Not straight away: the
// menu only appears once it has read a "you're paused" event a frame later, and
// unpausing before that leaves no menu at all.
//
// The wait is a short do-nothing animation on the menu itself: menus keep
// animating while the game is paused, so its end always arrives. (Game-time
// timers don't run while paused, which is why the first attempt never fired.)
@addField(PauseMenuBackgroundGameController)
let m_mpUnpauseAnim: ref<inkAnimProxy>;

@wrapMethod(PauseMenuBackgroundGameController)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpWorldKeepsRunning() {
        let root = this.GetRootWidget();
        let opacity = root.GetOpacity();
        let hold = new inkAnimTransparency();
        hold.SetStartTransparency(opacity);
        hold.SetEndTransparency(opacity);
        hold.SetDuration(0.3);
        let wait = new inkAnimDef();
        wait.AddInterpolator(hold);
        this.m_mpUnpauseAnim = root.PlayAnimation(wait);
        this.m_mpUnpauseAnim.RegisterToCallback(inkanimEventType.OnFinish, this, n"OnMpUnpauseBehindMenu");
    }
    return result;
}

@addMethod(PauseMenuBackgroundGameController)
protected cb func OnMpUnpauseBehindMenu(proxy: ref<inkAnimProxy>) -> Bool {
    if MpWorldKeepsRunning() {
        this.GetSystemRequestsHandler().UnpauseGame();
    }
    return true;
}

// ---------------------------------------------------------------- slow motion

@wrapMethod(TimeDilationHelper)
public final static func SetTimeDilation(requester: wref<GameObject>, reason: CName, timeDilation: Float, opt duration: Float, easeInCurve: CName, easeOutCurve: CName, allowMultipleTimeDilationSimultaneously: Bool, opt listener: ref<TimeDilationListener>) -> Bool {
    if MpWorldKeepsRunning() {
        return false;
    }
    return wrappedMethod(requester, reason, timeDilation, duration, easeInCurve, easeOutCurve, allowMultipleTimeDilationSimultaneously, listener);
}

@wrapMethod(TimeDilationHelper)
public final static func SetTimeDilationOnPlayer(requester: wref<GameObject>, reason: CName, timeDilation: Float, opt duration: Float, easeInCurve: CName, easeOutCurve: CName, allowMultipleTimeDilationSimultaneously: Bool, opt listener: ref<TimeDilationListener>) -> Bool {
    if MpWorldKeepsRunning() {
        return false;
    }
    return wrappedMethod(requester, reason, timeDilation, duration, easeInCurve, easeOutCurve, allowMultipleTimeDilationSimultaneously, listener);
}

// What the weapon wheel, the phone and the emote wheel use.
@wrapMethod(TimeDilationHelper)
public final static func SetTimeDilationWithProfile(requester: wref<GameObject>, profileName: script_ref<String>, enable: Bool, allowMultipleTimeDilationSimultaneously: Bool) -> Bool {
    if MpWorldKeepsRunning() {
        return false;
    }
    return wrappedMethod(requester, profileName, enable, allowMultipleTimeDilationSimultaneously);
}

// Deflect's slow motion goes straight to the time system, not through the helper.
@wrapMethod(PlayerPuppet)
protected func SetSlowMo(slowMoAmount: Float, slowMoDuration: Float) -> Void {
    if MpWorldKeepsRunning() {
        return;
    }
    wrappedMethod(slowMoAmount, slowMoDuration);
}

// ---------------------------------------------------------------- skipping time

// The clock is shared; one player can't move it from a menu. The skip time
// popup still opens and closes, it just doesn't skip.
@wrapMethod(TimeskipGameController)
private func Apply() -> Void {
    if MpWorldKeepsRunning() {
        return;
    }
    wrappedMethod();
}
