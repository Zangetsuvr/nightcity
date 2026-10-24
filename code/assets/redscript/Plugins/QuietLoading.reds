module CyberpunkMP.Plugins

// No Johnny on the loading screen.
//
// The loading screen you see when the city loads plays a voice-over (Johnny
// over the Dogtown image) and also uses that voice-over's animation to say
// "loading can finish now". An earlier version just removed the voice-over,
// and the loading bar then waited forever for a signal that never came.
//
// Now the voice-over is removed (every loading screen record names it in
// voTrackAnimName) and the "can finish" signal is given by us, as soon as the
// bar is full. Picture, tips and progress bar stay. This only applies while
// the server's mods are installed (the launcher puts your own mods back
// afterwards), so single player keeps it.

public class MpQuietLoadingScreens extends ScriptableTweak {
    protected cb func OnApply() -> Void {
        for record in TweakDBInterface.GetRecords(n"InitLoadingScreen") {
            let flat = record.GetID();
            TDBID.Append(flat, t".voTrackAnimName");
            TweakDBManager.SetFlat(flat, ToVariant(n"None"));
            TweakDBManager.UpdateRecord(record.GetID());
        }
    }
}

// Remembers whether the current loading screen has been told it may finish
// (one loading screen at a time; reset when a new one opens).
public class MpLoadingScreenState extends ScriptableService {
    public let skipSent: Bool;
}

public func MpLoadingState() -> ref<MpLoadingScreenState> {
    return GameInstance.GetScriptableServiceContainer().GetService(n"CyberpunkMP.Plugins.MpLoadingScreenState") as MpLoadingScreenState;
}

@wrapMethod(InitialLoadingScreenLogicController)
protected cb func OnInitialize() -> Bool {
    let state = MpLoadingState();
    if IsDefined(state) {
        state.skipSent = false;
    }
    return wrappedMethod();
}

@wrapMethod(InitialLoadingScreenLogicController)
protected final func SetLoadProgress(progress: Float) -> Void {
    wrappedMethod(progress);
    if progress < 0.99 {
        return;
    }
    let state = MpLoadingState();
    if IsDefined(state) && state.skipSent {
        return;
    }
    if IsDefined(state) {
        state.skipSent = true;
    }
    // What the voice-over's animation would have said at its end.
    this.OnAnimReadyForLoadingSkip();
}
