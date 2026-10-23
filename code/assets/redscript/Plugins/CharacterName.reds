module CyberpunkMP.Plugins

import Codeware.UI.*
import CyberpunkMP.*
import CyberpunkMP.World.*

// Character names.
//
// When a new game is started from the server launcher, the appearance screen of
// the character creator gets a "Character name" box at the top. While typing,
// the server is asked whether the name is free; Confirm is held until the name
// has been reserved for the player's Discord account. The name is then stored
// in the new game's save (MpCharacterIdentity below), so every save is its own
// character, and it's sent to the server when connecting.
//
// Started without the launcher (plain single player), nothing changes.

// Matches NameService::Status in code/client/App/Network/NameService.h.
enum MpNameStatus {
    Idle = 0,
    Checking = 1,
    Available = 2,
    Unavailable = 3,
    Reserving = 4,
    Reserved = 5,
    Error = 6,
}

// ---------------------------------------------------------------- the name in the save

public class MpCharacterIdentity extends ScriptableSystem {
    // Saved with the game, so each save keeps its own character name. Stored as
    // UTF-8 bytes because the game can't save String fields.
    private persistent let m_nameBytes: array<Uint8>;

    private func OnAttach() -> Void {
        this.Apply();
    }

    private func OnRestored(saveVersion: Int32, gameVersion: Int32) -> Void {
        this.Apply();
    }

    private func Apply() -> Void {
        let world = GameInstance.GetNetworkWorldSystem();

        // A game just made in the character creator has no name yet: take the
        // one reserved there. (The creator runs before this save exists.)
        if ArraySize(this.m_nameBytes) == 0 {
            let pending = world.TakePendingCharacterName();
            if StrLen(pending) > 0 {
                this.m_nameBytes = world.EncodeName(pending);
            }
        }

        world.SetCharacterName(this.GetName());
    }

    public func GetName() -> String {
        return GameInstance.GetNetworkWorldSystem().DecodeName(this.m_nameBytes);
    }

    public static func Get(game: GameInstance) -> ref<MpCharacterIdentity> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"CyberpunkMP.Plugins.MpCharacterIdentity") as MpCharacterIdentity;
    }
}

// ---------------------------------------------------------------- the name box

public class MpNameRow extends inkCustomController {
    private let m_menu: wref<characterCreationBodyMorphMenu>;
    private let m_input: ref<HubTextInput>;
    private let m_status: ref<inkText>;
    private let m_ticker: ref<inkAnimProxy>;

    private let m_text: String;
    private let m_secondsSinceEdit: Float;
    private let m_checkSent: Bool;
    private let m_confirmWhenReserved: Bool;

    private let m_lastShownStatus: Int32;
    private let m_lastShownMessage: String;


    protected cb func OnCreate() {
        let root = new inkVerticalPanel();
        root.SetName(n"mpCharacterName");
        root.SetChildMargin(inkMargin(0.0, 0.0, 0.0, 8.0));
        root.SetMargin(inkMargin(0.0, 0.0, 0.0, 40.0));

        let label = new inkText();
        label.SetName(n"label");
        label.SetText("CHARACTER NAME");
        label.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        label.SetFontStyle(n"Medium");
        label.SetFontSize(40);
        label.SetLetterCase(textLetterCase.UpperCase);
        label.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        label.BindProperty(n"tintColor", n"MainColors.Red");
        label.Reparent(root);

        this.m_input = HubTextInput.Create();
        this.m_input.SetName(n"input");
        this.m_input.SetMaxLength(24);
        this.m_input.SetDefaultText("Your character's name");
        this.m_input.SetWidth(720.0);
        this.m_input.Reparent(root);

        this.m_status = new inkText();
        this.m_status.SetName(n"status");
        this.m_status.SetText("3 to 24 letters. Other players will see this name.");
        this.m_status.SetFontFamily("base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily");
        this.m_status.SetFontStyle(n"Regular");
        this.m_status.SetFontSize(30);
        this.m_status.SetStyle(r"base\\gameplay\\gui\\common\\main_colors.inkstyle");
        this.m_status.BindProperty(n"tintColor", n"MainColors.Blue");
        this.m_status.Reparent(root);

        this.SetRootWidget(root);
    }

    protected cb func OnInitialize() {
        this.m_input.RegisterToCallback(n"OnInput", this, n"OnNameInput");
        this.m_lastShownStatus = -1;
        this.StartTicker();
    }

    protected cb func OnUninitialize() {
        if IsDefined(this.m_ticker) {
            this.m_ticker.Stop();
        }
    }

    public func SetMenu(menu: ref<characterCreationBodyMorphMenu>) {
        this.m_menu = menu;
    }

    public func GetText() -> String {
        return this.m_input.GetText();
    }

    public func SetText(text: String) {
        this.m_input.SetText(text);
        this.OnNameInput(null);
    }

    // ------------------------------------------------------------ typing

    protected cb func OnNameInput(widget: wref<inkWidget>) {
        let text = this.CleanName(this.m_input.GetText());
        if NotEquals(text, this.m_text) {
            this.m_text = text;
            this.m_secondsSinceEdit = 0.0;
            this.m_checkSent = false;
            this.m_confirmWhenReserved = false;
            this.m_lastShownStatus = -1;
            this.m_lastShownMessage = "";
            this.ShowLocal();
        }
    }

    // Trims spaces at both ends and squeezes double spaces, so "  Jackie  Welles "
    // is checked as "Jackie Welles".
    private func CleanName(text: String) -> String {
        let out = "";
        let lastWasSpace = true;
        let i = 0;
        while i < StrLen(text) {
            let c = StrMid(text, i, 1);
            if Equals(c, " ") {
                if !lastWasSpace {
                    out = out + c;
                }
                lastWasSpace = true;
            } else {
                out = out + c;
                lastWasSpace = false;
            }
            i += 1;
        }
        if StrLen(out) > 0 && Equals(StrRight(out, 1), " ") {
            out = StrLeft(out, StrLen(out) - 1);
        }
        return out;
    }

    // Quick checks that need no server, shown immediately.
    private func ShowLocal() {
        let length = StrLen(this.m_text);
        if length == 0 {
            this.SetStatus("3 to 24 letters. Other players will see this name.", n"MainColors.Blue");
        } else {
            if length < 3 {
                this.SetStatus("Too short: at least 3 characters.", n"MainColors.Red");
            } else {
                this.SetStatus("Checking...", n"MainColors.Blue");
            }
        }
    }

    // ------------------------------------------------------------ polling

    private func StartTicker() {
        let tick = new inkAnimTextValueProgress();
        tick.SetStartProgress(0.0);
        tick.SetEndProgress(0.0);
        tick.SetDuration(MpNameRow.TickSeconds());

        let def = new inkAnimDef();
        def.AddInterpolator(tick);

        let opts: inkAnimOptions;
        opts.loopInfinite = true;
        opts.loopType = inkanimLoopType.Cycle;

        this.m_ticker = this.GetRootWidget().PlayAnimationWithOptions(def, opts);
        this.m_ticker.RegisterToCallback(inkanimEventType.OnStartLoop, this, n"OnTick");
    }

    protected cb func OnTick(anim: ref<inkAnimProxy>) {
        let world = GameInstance.GetNetworkWorldSystem();
        this.m_secondsSinceEdit += MpNameRow.TickSeconds();

        // Ask the server once the player has paused typing.
        if !this.m_checkSent && StrLen(this.m_text) >= 3 && this.m_secondsSinceEdit >= 0.6 {
            this.m_checkSent = true;
            world.RequestNameCheck(this.m_text);
            return;
        }

        // Only show answers about the text currently in the box.
        if !Equals(world.GetNameStatusName(), this.m_text) || StrLen(this.m_text) < 3 {
            return;
        }

        let status = world.GetNameStatus();
        let message = world.GetNameStatusMessage();
        if status == this.m_lastShownStatus && Equals(message, this.m_lastShownMessage) {
            return;
        }
        this.m_lastShownStatus = status;
        this.m_lastShownMessage = message;

        switch status {
            case 2: // Available
                this.SetStatus("Available", n"MainColors.ActiveGreen");
                break;
            case 5: // Reserved
                this.SetStatus("Reserved for you", n"MainColors.ActiveGreen");
                if this.m_confirmWhenReserved {
                    this.m_confirmWhenReserved = false;
                    this.ConfirmMenu();
                }
                break;
            case 3: // Unavailable
                this.m_confirmWhenReserved = false;
                this.SetStatus(message, n"MainColors.Red");
                break;
            case 6: // Error
                this.m_confirmWhenReserved = false;
                this.SetStatus(message, n"MainColors.Red");
                break;
            case 4: // Reserving
                this.SetStatus("Reserving...", n"MainColors.Blue");
                break;
            default:
                this.SetStatus("Checking...", n"MainColors.Blue");
                break;
        }
    }

    private func SetStatus(text: String, color: CName) {
        this.m_status.SetText(text);
        this.m_status.BindProperty(n"tintColor", color);
    }

    // ------------------------------------------------------------ confirming

    // Called when the player presses Confirm in the creator. Returns true if
    // the creator may go on (the name is reserved), false to hold it.
    public func TryConfirm() -> Bool {
        let world = GameInstance.GetNetworkWorldSystem();
        let status = world.GetNameStatus();
        let current = Equals(world.GetNameStatusName(), this.m_text);

        if StrLen(this.m_text) < 3 {
            this.SetStatus("Name your character before continuing.", n"MainColors.Red");
            return false;
        }

        if current && status == 5 /* Reserved */ {
            world.SetPendingCharacterName(this.m_text);
            return true;
        }

        if current && (status == 3 /* Unavailable */ || status == 6 /* Error */) {
            this.SetStatus(world.GetNameStatusMessage(), n"MainColors.Red");
            return false;
        }

        // Free or not checked yet: reserve it now, and continue automatically
        // once the server says yes.
        this.m_confirmWhenReserved = true;
        this.m_checkSent = true;
        this.m_lastShownStatus = -1;
        world.RequestNameReserve(this.m_text);
        this.SetStatus("Reserving...", n"MainColors.Blue");
        return false;
    }

    private func ConfirmMenu() {
        if IsDefined(this.m_menu) {
            this.m_menu.ConfirmCustomizedCharacter();
        }
    }

    public static func TickSeconds() -> Float {
        return 0.2;
    }

    public static func Create() -> ref<MpNameRow> {
        let self = new MpNameRow();
        self.CreateInstance();
        return self;
    }
}

// ---------------------------------------------------------------- hooks into the creator

@addField(characterCreationBodyMorphMenu)
private let m_mpNameRow: ref<MpNameRow>;

// Runs only while creating a new character (not when editing appearance later).
@wrapMethod(characterCreationBodyMorphMenu)
public final func CreateVoiceOverSwitcher() -> Void {
    wrappedMethod();

    if !GameInstance.GetNetworkWorldSystem().HasServerSession() {
        return;
    }

    let list = inkCompoundRef.Get(this.m_optionsList) as inkCompoundWidget;
    if !IsDefined(list) {
        return;
    }

    // The game can rebuild the options list, which removes our row. Add it
    // again if it's gone, keeping what the player had typed.
    if IsDefined(list.GetWidget(n"mpCharacterName")) {
        return;
    }

    let previousText = "";
    if IsDefined(this.m_mpNameRow) {
        previousText = this.m_mpNameRow.GetText();
    }

    let row = MpNameRow.Create();
    row.SetMenu(this);
    row.Reparent(list, this);
    list.ReorderChild(row.GetRootWidget(), 0);
    if StrLen(previousText) > 0 {
        row.SetText(previousText);
    }
    this.m_mpNameRow = row;
}

@wrapMethod(characterCreationBodyMorphMenu)
public final func ConfirmCustomizedCharacter() -> Void {
    if IsDefined(this.m_mpNameRow) && !this.m_mpNameRow.TryConfirm() {
        return; // held until the name is reserved
    }
    wrappedMethod();
}
