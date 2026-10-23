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
// From the launcher, the screens before body type answer themselves: always
// Phantom Liberty's start (which the clean start archive turns into "no
// prologue, no story"), normal difficulty and Street Kid. Each screen still
// runs exactly as the game expects, it just isn't shown and picks for the
// player a moment after it opens.

public func MpSkipsNewGameChoices() -> Bool {
    let world = GameInstance.GetNetworkWorldSystem();
    return IsDefined(world) && world.HasServerSession();
}

// Calls back into a menu shortly after it opens, once it's fully set up.
public class MpMenuAdvance extends DelayCallback {
    public let expansion: wref<ExpansionNewGame>;
    public let difficulty: wref<DifficultySelectionMenu>;
    public let lifePath: wref<CharacterCreationBackstorySelectionMenu>;

    public func Call() -> Void {
        if IsDefined(this.expansion) {
            this.expansion.MpChooseStart();
        }
        if IsDefined(this.difficulty) {
            this.difficulty.MpChooseDifficulty();
        }
        if IsDefined(this.lifePath) {
            this.lifePath.MpChooseLifePath();
        }
    }
}

public func MpAdvanceSoon(callback: ref<MpMenuAdvance>) -> Void {
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(callback, 0.2, false);
}

@wrapMethod(ExpansionNewGame)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        this.GetRootWidget().SetVisible(false);
        let next = new MpMenuAdvance();
        next.expansion = this;
        MpAdvanceSoon(next);
    }
    return result;
}

@addMethod(ExpansionNewGame)
public func MpChooseStart() -> Void {
    this.m_characterCustomizationState.SetIsExpansionStandalone(true);
    this.NextMenu();
}

@wrapMethod(DifficultySelectionMenu)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        this.GetRootWidget().SetVisible(false);
        let next = new MpMenuAdvance();
        next.difficulty = this;
        MpAdvanceSoon(next);
    }
    return result;
}

@addMethod(DifficultySelectionMenu)
public func MpChooseDifficulty() -> Void {
    this.SetDifficulty(gameDifficulty.Easy);
}

@wrapMethod(CharacterCreationBackstorySelectionMenu)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        this.GetRootWidget().SetVisible(false);
        let next = new MpMenuAdvance();
        next.lifePath = this;
        MpAdvanceSoon(next);
    }
    return result;
}

@addMethod(CharacterCreationBackstorySelectionMenu)
public func MpChooseLifePath() -> Void {
    this.m_characterCustomizationState.SetLifePath(t"LifePaths.StreetKid");
    this.NextMenu();
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
