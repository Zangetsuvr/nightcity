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

// New Game, straight to making your character.
//
// From the launcher, New Game skips the start choice, difficulty and lifepath
// screens: it's always Phantom Liberty's start (which the clean start archive
// turns into "no prologue, no story"), normal difficulty and Street Kid. The
// player goes straight to picking a body type and the character creator.
@wrapMethod(MenuScenario_SingleplayerMenu)
protected cb func OnNewGame() -> Bool {
    let world = GameInstance.GetNetworkWorldSystem();
    let game = GetGameInstance();
    let ccSystem = GameInstance.GetCharacterCustomizationSystem(game);
    if !IsDefined(world) || !world.HasServerSession() || !IsDefined(ccSystem)
        || !this.GetSystemRequestsHandler().IsAdditionalContentEnabled(n"EP1") {
        return wrappedMethod();
    }

    this.CloseSubMenu();

    // What the skipped screens would have set.
    ccSystem.InitializeState();
    let state = ccSystem.GetState();
    state.SetIsExpansionStandalone(true);
    state.SetLifePath(t"LifePaths.StreetKid");
    GameInstance.GetStatsDataSystem(game).SetDifficulty(gameDifficulty.Easy);

    // The lifepath screen normally opens this backdrop and leaves it up for the
    // body type screen.
    this.GetMenusState().OpenMenu(n"character_customization_background");
    this.SwitchToScenario(n"MenuScenario_BodyTypeSelection");
    return true;
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
