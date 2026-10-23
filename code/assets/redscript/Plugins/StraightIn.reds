module CyberpunkMP.Plugins

import CyberpunkMP.World.*

// Straight in.
//
// When the game is started from the server launcher, the main menu doesn't wait
// for a click the first time it opens:
//   - an account with a character on the server loads the newest save,
//   - an account without one starts a New Game, which (with the clean start
//     archive) goes through the character creator and into the city with no
//     prologue and no story.
// Once a world has loaded, the game connects to the server by itself.
//
// Started without the launcher, nothing here does anything. Going back to the
// main menu later in the same session shows the normal menu.

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnSavesForLoadReady(saves: array<String>) -> Bool {
    let result = wrappedMethod(saves);

    let world = GameInstance.GetNetworkWorldSystem();
    if !IsDefined(world) || !world.HasServerSession() || !world.TakeAutoStart() {
        return result;
    }

    if world.GetAccountCharacterCount() > 0 && ArraySize(saves) > 0 {
        this.GetSystemRequestsHandler().LoadLastCheckpoint(false);
    } else {
        this.m_menuEventDispatcher.SpawnEvent(n"OnNewGame");
    }
    return result;
}

// Connects a few seconds after the player is in the world.
public class MpAutoConnect extends ScriptableSystem {
    private func OnPlayerAttach(request: ref<PlayerAttachRequest>) -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(world) || !world.HasServerSession() {
            return;
        }
        let connect = new MpAutoConnectCallback();
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(connect, 3.0, false);
    }
}

public class MpAutoConnectCallback extends DelayCallback {
    public func Call() -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(world) || world.IsConnected() {
            return;
        }
        // A save without a character name is a plain single-player save: the
        // server would only refuse it, so don't try.
        if StrLen(world.GetCharacterName()) == 0 {
            return;
        }
        world.Connect();
    }
}
