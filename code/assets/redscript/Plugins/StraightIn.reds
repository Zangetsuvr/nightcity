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
        // Load the newest save, but only once the game has checked it can: a
        // save from another game version reads as damaged. That check arrives
        // in OnSaveMetadataReady below; if it never does, make a character.
        this.m_mpWaitingForSave = true;
        let fallback = new MpMenuAdvance();
        fallback.mainMenu = this;
        MpAdvanceSoon(fallback, 4.0);
    } else {
        // Give the menu a moment to finish setting up, as a player would.
        let next = new MpMenuAdvance();
        next.mainMenu = this;
        MpAdvanceSoon(next, 1.0);
    }
    return result;
}

@addField(SingleplayerMenuGameController)
let m_mpWaitingForSave: Bool;

@addField(SingleplayerMenuGameController)
let m_mpStarted: Bool;

@wrapMethod(SingleplayerMenuGameController)
protected cb func OnSaveMetadataReady(info: ref<SaveMetadataInfo>) -> Bool {
    let result = wrappedMethod(info);
    if this.m_mpWaitingForSave && info.saveIndex == 0 {
        this.m_mpWaitingForSave = false;
        if info.isValid {
            this.m_mpStarted = true;
            this.GetSystemRequestsHandler().LoadLastCheckpoint(false);
        } else {
            this.MpStartNewGame();
        }
    }
    return result;
}

@addMethod(SingleplayerMenuGameController)
public func MpStartNewGame() -> Void {
    if this.m_mpStarted {
        return;
    }
    this.m_mpStarted = true;
    this.m_mpWaitingForSave = false;
    this.m_menuEventDispatcher.SpawnEvent(n"OnNewGame");
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
    public let mainMenu: wref<SingleplayerMenuGameController>;
    public let expansion: wref<ExpansionNewGame>;
    public let difficulty: wref<DifficultySelectionMenu>;
    public let lifePath: wref<CharacterCreationBackstorySelectionMenu>;
    public let bodyType: wref<CharacterCreationGenderSelectionMenu>;

    public func Call() -> Void {
        if IsDefined(this.mainMenu) {
            this.mainMenu.MpStartNewGame();
        }
        if IsDefined(this.expansion) {
            this.expansion.MpChooseStart();
        }
        if IsDefined(this.difficulty) {
            this.difficulty.MpChooseDifficulty();
        }
        if IsDefined(this.lifePath) {
            this.lifePath.MpChooseLifePath();
        }
        if IsDefined(this.bodyType) {
            this.bodyType.MpShowPreviews();
        }
    }
}

public func MpAdvanceSoon(callback: ref<MpMenuAdvance>, opt seconds: Float) -> Void {
    GameInstance.GetDelaySystem(GetGameInstance()).DelayCallback(callback, seconds > 0.0 ? seconds : 0.2, false);
}

@wrapMethod(ExpansionNewGame)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        this.GetRootWidget().SetVisible(false);
        let next = new MpMenuAdvance();
        next.expansion = this;
        // This screen sets up the character creator's state; let it finish.
        MpAdvanceSoon(next, 2.0);
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
        MpAdvanceSoon(next, 0.5);
    }
    return result;
}

@addMethod(DifficultySelectionMenu)
public func MpChooseDifficulty() -> Void {
    // gameDifficulty.Easy is the second option on the screen ("Normal").
    GameInstance.GetStatsDataSystem(GetGameInstance()).SetDifficulty(gameDifficulty.Easy);
    this.NextMenu();
}

@wrapMethod(CharacterCreationBackstorySelectionMenu)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        this.GetRootWidget().SetVisible(false);
        let next = new MpMenuAdvance();
        next.lifePath = this;
        // The body type previews start loading behind this screen; give them a
        // moment, as a player reading the lifepaths would.
        MpAdvanceSoon(next, 1.5);
    }
    return result;
}

@addMethod(CharacterCreationBackstorySelectionMenu)
public func MpChooseLifePath() -> Void {
    this.m_characterCustomizationState.SetLifePath(t"LifePaths.StreetKid");
    this.NextMenu();
}

// Body type: the two previews only appear when the game says their puppets are
// ready. If that moment passed before this screen opened, show them anyway.
@addField(CharacterCreationGenderSelectionMenu)
let m_mpPreviewsShown: Bool;

@wrapMethod(CharacterCreationGenderSelectionMenu)
protected cb func OnInitialize() -> Bool {
    let result = wrappedMethod();
    if MpSkipsNewGameChoices() {
        let check = new MpMenuAdvance();
        check.bodyType = this;
        MpAdvanceSoon(check, 3.0);
    }
    return result;
}

@wrapMethod(CharacterCreationGenderSelectionMenu)
protected cb func OnPuppetReadyToBeDisplayed(evt: ref<gameuiPuppetPreview_ReadyToBeDisplayed>) -> Bool {
    this.m_mpPreviewsShown = true;
    return wrappedMethod(evt);
}

@addMethod(CharacterCreationGenderSelectionMenu)
public func MpShowPreviews() -> Void {
    if this.m_mpPreviewsShown {
        return;
    }
    this.m_mpPreviewsShown = true;
    this.PlayLibraryAnimation(n"male_preview_intro");
    this.PlayLibraryAnimation(n"female_preview_intro");
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
