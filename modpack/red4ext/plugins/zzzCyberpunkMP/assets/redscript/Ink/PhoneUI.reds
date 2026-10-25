module CyberpunkMP.Ink

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Plugins.*

// The players' phone, opened with the phone key while on the server (the
// game's own phone stays for single player). Same look and keys as the job
// board: up/down choose, right/left between the list and the buttons, Enter
// does it, Esc closes.
//
// Left: requests to swap numbers, your contacts (with who's online), players
// standing near you, and anyone you've blocked. Right: the last texts with the
// selected contact and what you can do.

public class MpPhoneRow {
    // "request", "contact", "nearby", "blocked"
    public let kind: String;
    public let name: String;
    public let online: Bool;
    public let meters: Int32;
    public let sent: Bool;
}

public class MpPhoneLine {
    public let with: String;
    public let fromMe: Bool;
    public let body: String;
    public let time: String;
}

public class MpPhone extends ScriptableSystem {
    private let m_controller: wref<MultiplayerGameController>;
    private let m_canvas: ref<inkCanvas>;
    private let m_open: Bool;
    private let m_wantOpen: Bool;
    private let m_rows: array<ref<MpPhoneRow>>;
    private let m_lines: array<ref<MpPhoneLine>>;
    private let m_selected: Int32;
    private let m_focus: Int32;
    private let m_action: Int32;
    private let m_armed: String;
    private let m_lastSender: String;

    public static func Get() -> ref<MpPhone> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Ink.MpPhone") as MpPhone;
    }

    public func IsOpen() -> Bool {
        return this.m_open;
    }

    public func SetLastSender(name: String) -> Void {
        this.m_lastSender = name;
    }

    public func GetLastSender() -> String {
        return this.m_lastSender;
    }

    // The phone key: ask the server for the current state; it opens on the answer.
    public func RequestOpen() -> Void {
        if this.m_open {
            this.Close();
            return;
        }
        this.m_wantOpen = true;
        PhoneServer.OpenPhone();
    }

    public func OnData(payload: String) -> Void {
        let keepName = "";
        let current = this.Selected();
        if IsDefined(current) {
            keepName = current.kind + "|" + current.name;
        }
        ArrayClear(this.m_rows);
        ArrayClear(this.m_lines);
        let kinds: array<String> = ["R", "C", "N", "B"];
        for k in kinds {
            for record in StrSplit(payload, "^") {
                let f = StrSplit(record, "~");
                if ArraySize(f) >= 2 && Equals(f[0], k) {
                    let row = new MpPhoneRow();
                    row.name = f[1];
                    if Equals(k, "R") { row.kind = "request"; }
                    if Equals(k, "C") { row.kind = "contact"; row.online = ArraySize(f) >= 3 && Equals(f[2], "1"); }
                    if Equals(k, "N") { row.kind = "nearby"; row.meters = ArraySize(f) >= 3 ? StringToInt(f[2]) : 0; row.sent = ArraySize(f) >= 4 && Equals(f[3], "1"); }
                    if Equals(k, "B") { row.kind = "blocked"; }
                    ArrayPush(this.m_rows, row);
                }
            }
        }
        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            if ArraySize(f) >= 5 && Equals(f[0], "T") {
                let line = new MpPhoneLine();
                line.with = f[1];
                line.fromMe = Equals(f[2], "1");
                line.body = f[3];
                line.time = f[4];
                ArrayPush(this.m_lines, line);
            }
        }
        // Stay on the same person after a refresh.
        this.m_selected = 0;
        let i = 0;
        for row in this.m_rows {
            if Equals(row.kind + "|" + row.name, keepName) {
                this.m_selected = i;
            }
            i += 1;
        }
        this.m_armed = "";
        if this.m_open {
            let acts = this.ActionsFor(this.Selected());
            let n = ArraySize(acts);
            if this.m_action >= n {
                this.m_action = 0;
            }
            this.Redraw();
            return;
        }
        if this.m_wantOpen {
            this.m_wantOpen = false;
            let controller = GameInstance.GetNetworkWorldSystem().GetAppearanceSystem().m_controller;
            if IsDefined(controller) {
                controller.OpenPhonePanel();
            }
        }
    }

    public func Open(controller: ref<MultiplayerGameController>) -> Void {
        this.m_controller = controller;
        this.m_open = true;
        this.m_focus = 0;
        this.m_action = 0;
        this.Redraw();
    }

    public func Close() -> Void {
        this.m_open = false;
        this.m_wantOpen = false;
        if IsDefined(this.m_canvas) {
            let parent = this.m_canvas.GetParentWidget() as inkCompoundWidget;
            if IsDefined(parent) {
                parent.RemoveChild(this.m_canvas);
            }
            this.m_canvas = null;
        }
        if IsDefined(this.m_controller) {
            this.m_controller.OnJobBoardClosed();
        }
    }

    private func Selected() -> ref<MpPhoneRow> {
        return this.m_selected >= 0 && this.m_selected < ArraySize(this.m_rows) ? this.m_rows[this.m_selected] : null;
    }

    private func ActionsFor(row: ref<MpPhoneRow>) -> array<String> {
        let a: array<String>;
        if !IsDefined(row) {
            return a;
        }
        switch row.kind {
            case "request":
                ArrayPush(a, "accept");
                ArrayPush(a, "decline");
                ArrayPush(a, "block");
                break;
            case "contact":
                ArrayPush(a, "text");
                if row.online {
                    ArrayPush(a, "ping");
                }
                ArrayPush(a, "remove");
                ArrayPush(a, "block");
                break;
            case "nearby":
                if !row.sent {
                    ArrayPush(a, "share");
                }
                ArrayPush(a, "block");
                break;
            case "blocked":
                ArrayPush(a, "unblock");
                break;
        }
        return a;
    }

    private func Label(action: String) -> String {
        if Equals(this.m_armed, action) {
            return "PRESS ENTER AGAIN TO CONFIRM";
        }
        switch action {
            case "accept": return "SAVE THEIR NUMBER";
            case "decline": return "DECLINE";
            case "text": return "SEND A TEXT";
            case "ping": return "SEND MY LOCATION";
            case "remove": return "REMOVE CONTACT";
            case "block": return "BLOCK";
            case "share": return "SHARE MY NUMBER";
            case "unblock": return "UNBLOCK";
        }
        return action;
    }

    private func NeedsConfirm(action: String) -> Bool {
        return Equals(action, "remove") || Equals(action, "block");
    }

    private func Run(action: String) -> Void {
        let row = this.Selected();
        if !IsDefined(row) {
            return;
        }
        if this.NeedsConfirm(action) && NotEquals(this.m_armed, action) {
            this.m_armed = action;
            this.Redraw();
            return;
        }
        this.m_armed = "";
        switch action {
            case "accept":
                PhoneServer.AnswerRequest(row.name, true);
                break;
            case "decline":
                PhoneServer.AnswerRequest(row.name, false);
                break;
            case "text":
                // Typed in the chat box: "@Name: message".
                this.Close();
                MpOpenChatWith("@" + row.name + ": ");
                return;
            case "ping":
                PhoneServer.PingLocation(row.name);
                break;
            case "remove":
                PhoneServer.RemoveContact(row.name);
                break;
            case "block":
                PhoneServer.SetBlocked(row.name, true);
                break;
            case "unblock":
                PhoneServer.SetBlocked(row.name, false);
                break;
            case "share":
                PhoneServer.ShareContact(row.name);
                break;
        }
        this.Redraw();
    }

    public func HandleAction(name: CName, pressed: Bool) -> Bool {
        if !this.m_open || !pressed {
            return this.m_open;
        }
        if Equals(name, n"cancel") {
            if StrLen(this.m_armed) > 0 {
                this.m_armed = "";
                this.Redraw();
            } else {
                this.Close();
            }
            return true;
        }
        let up = Equals(name, n"popup_moveUp") || Equals(name, n"popup_moveUp_left_stick_up");
        let down = Equals(name, n"popup_moveDown") || Equals(name, n"popup_moveUp_left_stick_down");
        let left = Equals(name, n"popup_moveLeft") || Equals(name, n"popup_prior");
        let right = Equals(name, n"popup_moveRight") || Equals(name, n"popup_next");
        let proceed = Equals(name, n"proceed");
        let rows = ArraySize(this.m_rows);
        let actions = this.ActionsFor(this.Selected());
        if up || down || left || right {
            this.m_armed = "";
        }
        if this.m_focus == 0 {
            if up && rows > 0 { this.m_selected = (this.m_selected + rows - 1) % rows; this.m_action = 0; }
            if down && rows > 0 { this.m_selected = (this.m_selected + 1) % rows; this.m_action = 0; }
            if right && ArraySize(actions) > 0 { this.m_focus = 1; }
            if proceed && ArraySize(actions) > 0 {
                if ArraySize(actions) == 1 {
                    this.Run(actions[0]);
                } else {
                    this.m_focus = 1;
                }
                if this.m_open { this.Redraw(); }
                return true;
            }
        } else {
            let n = ArraySize(actions);
            if up && n > 0 { this.m_action = (this.m_action + n - 1) % n; }
            if down && n > 0 { this.m_action = (this.m_action + 1) % n; }
            if left { this.m_focus = 0; }
            if proceed && this.m_action < n {
                this.Run(actions[this.m_action]);
                if this.m_open { this.Redraw(); }
                return true;
            }
        }
        this.Redraw();
        return true;
    }

    private func SectionTitle(kind: String) -> String {
        switch kind {
            case "request": return "REQUESTS";
            case "contact": return "CONTACTS";
            case "nearby": return "NEARBY";
            case "blocked": return "BLOCKED";
        }
        return "";
    }

    private func Detail(row: ref<MpPhoneRow>) -> String {
        switch row.kind {
            case "request": return "Wants to swap numbers with you.";
            case "contact": return row.online ? "Online now." : "Offline. Texts wait for them.";
            case "nearby": return row.sent ? "Number sent. Waiting for them to save it." : IntToString(row.meters) + " m away. Swap numbers?";
            case "blocked": return "Can't send you requests or texts.";
        }
        return "";
    }

    private func Redraw() -> Void {
        if !this.m_open || !IsDefined(this.m_controller) {
            return;
        }
        let root = this.m_controller.GetRootCompoundWidget();
        if !IsDefined(root) {
            return;
        }
        if !IsDefined(this.m_canvas) {
            let canvas = new inkCanvas();
            canvas.SetName(n"mp_phone");
            canvas.SetAnchor(inkEAnchor.TopLeft);
            canvas.SetAnchorPoint(new Vector2(0.0, 0.0));
            canvas.SetSize(new Vector2(1920.0, 1080.0));
            canvas.SetInteractive(false);
            canvas.Reparent(root);
            this.m_canvas = canvas;
        }
        let size = root.GetSize();
        let scale = size.X > 1.0 ? size.X / 1920.0 : 2.0;
        let offsetY = size.Y > 1.0 ? (size.Y - 1080.0 * scale) / 2.0 : 0.0;
        this.m_canvas.SetMargin(new inkMargin(0.0, offsetY, 0.0, 0.0));
        this.m_canvas.SetRenderTransformPivot(new Vector2(0.0, 0.0));
        this.m_canvas.SetScale(new Vector2(scale, scale));
        this.m_canvas.RemoveAllChildren();

        let c = this.m_canvas;
        let x = 250.0;
        let y = 130.0;
        let w = 1420.0;
        let h = 820.0;
        MpJbRect(c, x, y, w, h, MpJbPlate(), 0.95);
        MpJbRect(c, x, y, w, 3.0, MpJbCyan(), 1.0);
        MpJbRect(c, x, y, 3.0, h, MpJbRedDim(), 1.0);
        MpJbText(c, x + 40.0, y + 28.0, "PHONE", 54, n"Bold", MpJbCyan());
        MpJbText(c, x + 260.0, y + 50.0, "Swap numbers with players near you. Reply to a text with /r message", 22, n"Regular", MpJbInkDim());
        MpJbRect(c, x + 40.0, y + 108.0, w - 80.0, 1.0, MpJbRedDim(), 1.0);

        let lx = x + 40.0;
        let ly = y + 128.0;
        if ArraySize(this.m_rows) == 0 {
            MpJbText(c, lx, ly, "No contacts yet.", 30, n"Bold", MpJbInk());
            MpJbText(c, lx, ly + 44.0, "Stand near another player and open your phone:", 24, n"Regular", MpJbInkDim());
            MpJbText(c, lx, ly + 78.0, "they show up under NEARBY, where you can share your number.", 24, n"Regular", MpJbInkDim());
        }

        // List.
        let i = 0;
        let lastKind = "";
        let first = Max(0, this.m_selected - 10);
        for row in this.m_rows {
            if i >= first && ly < y + h - 90.0 {
                if NotEquals(row.kind, lastKind) {
                    ly += 6.0;
                    MpJbText(c, lx, ly, this.SectionTitle(row.kind), 20, n"Bold", Equals(row.kind, "request") ? MpJbGold() : MpJbInkFaint());
                    ly += 30.0;
                }
                let selected = i == this.m_selected;
                if selected {
                    MpJbRect(c, lx - 10.0, ly - 4.0, 470.0, 46.0, MpJbRed(), this.m_focus == 0 ? 0.22 : 0.10);
                    MpJbRect(c, lx - 10.0, ly - 4.0, 4.0, 46.0, MpJbRed(), 1.0);
                }
                MpJbText(c, lx + 6.0, ly + 2.0, row.name, 28, Equals(row.kind, "contact") ? n"Bold" : n"Medium", selected ? MpJbInk() : MpJbInkDim());
                if Equals(row.kind, "contact") && row.online {
                    MpJbRect(c, lx + 420.0, ly + 14.0, 12.0, 12.0, MpJbCyan(), 1.0);
                }
                if Equals(row.kind, "nearby") {
                    MpJbText(c, lx + 380.0, ly + 8.0, IntToString(row.meters) + " m", 18, n"Bold", MpJbInkFaint());
                }
                ly += 48.0;
            }
            lastKind = row.kind;
            i += 1;
        }

        // Details, texts and buttons.
        MpJbRect(c, x + 540.0, y + 128.0, 1.0, h - 200.0, MpJbRedDim(), 1.0);
        let row = this.Selected();
        if IsDefined(row) {
            let dx = x + 580.0;
            MpJbText(c, dx, y + 130.0, StrUpper(row.name), 48, n"Bold", MpJbInk());
            MpJbText(c, dx, y + 196.0, this.Detail(row), 24, n"Regular", MpJbInkDim());
            let ty = y + 250.0;
            if Equals(row.kind, "contact") {
                let any = false;
                let count = 0;
                for line in this.m_lines {
                    if Equals(line.with, row.name) {
                        count += 1;
                    }
                }
                // The last five fit above the buttons.
                let skip = count - 5;
                for line in this.m_lines {
                    if Equals(line.with, row.name) && skip > 0 {
                        skip -= 1;
                    } else if Equals(line.with, row.name) {
                        any = true;
                        let who = line.fromMe ? "YOU" : StrUpper(row.name);
                        MpJbText(c, dx, ty, who + "   " + line.time, 16, n"Bold", line.fromMe ? MpJbCyan() : MpJbGold());
                        MpJbText(c, dx, ty + 20.0, MpPhoneClip(line.body, 70), 22, n"Regular", MpJbInk());
                        ty += 52.0;
                    }
                }
                if !any {
                    MpJbText(c, dx, ty, "No texts yet.", 22, n"Regular", MpJbInkFaint());
                    ty += 40.0;
                }
                ty += 10.0;
            }
            let by = MaxF(ty, y + 250.0);
            let a = 0;
            for action in this.ActionsFor(row) {
                let focused = this.m_focus == 1 && a == this.m_action;
                let danger = Equals(action, "remove") || Equals(action, "block");
                MpJbRect(c, dx, by, 520.0, 48.0, danger ? MpJbRed() : MpJbRedDim(), focused ? 1.0 : 0.5);
                if focused {
                    MpJbRect(c, dx + 520.0, by, 8.0, 48.0, MpJbCyan(), 1.0);
                }
                MpJbText(c, dx + 18.0, by + 9.0, this.Label(action), 26, n"Bold", focused ? MpJbPlate() : MpJbInk());
                by += 58.0;
                a += 1;
            }
        }
        MpJbText(c, x + 40.0, y + h - 46.0, "UP / DOWN  choose        RIGHT  buttons        ENTER  select        ESC  close", 22, n"Medium", MpJbInkFaint());
    }
}

public func MpPhoneClip(text: String, max: Int32) -> String {
    if StrLen(text) <= max {
        return text;
    }
    return StrLeft(text, max - 3) + "...";
}
