module CyberpunkMP.Plugins

// No Johnny on the loading screen.
//
// Phantom Liberty's loading screen plays a voice-over track (Johnny talking
// over the Dogtown image). Every loading screen record names its voice-over in
// voTrackAnimName; clearing it leaves the picture and the progress bar, with
// no voice. This only runs while the server's mods are installed (the
// launcher puts your own mods back afterwards), so single player keeps it.
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
