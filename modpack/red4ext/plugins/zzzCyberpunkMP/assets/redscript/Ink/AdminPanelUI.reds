module CyberpunkMP.Ink

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Plugins.*

// The admin panel, opened with /admin in chat (only for admins; the server
// refuses everyone else). Same look and keys as the job board:
// up/down choose, right/left between the list and the buttons, Enter does it,
// Esc closes.
//
// Left: teleport to your map waypoint, heal yourself, every player online,
// and the saved places. Right: what you can do with the selected one.

public class MpAdminRow {
    // "waypoint", "self", "player", "place"
    public let kind: String;
    public let name: String;
    public let detail: String;
    public let isAdmin: Bool;
    public let isMe: Bool;
    public let position: Vector4;
}

public class MpAdminPanel extends ScriptableSystem {
    private let m_controller: wref<MultiplayerGameController>;
    private let m_canvas: ref<inkCanvas>;
    private let m_open: Bool;
    private let m_rows: array<ref<MpAdminRow>>;
    private let m_selected: Int32;
    private let m_focus: Int32;
    private let m_action: Int32;
    // An action waiting for a second Enter (kick, ban, remove admin, delete place).
    private let m_armed: String;

    public static func Get() -> ref<MpAdminPanel> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Ink.MpAdminPanel") as MpAdminPanel;
    }

    public func IsOpen() -> Bool {
        return this.m_open;
    }

    // The server's answer to /admin (and refreshed after changes).
    public func OnData(payload: String) -> Void {
        ArrayClear(this.m_rows);
        let waypoint = new MpAdminRow();
        waypoint.kind = "waypoint";
        waypoint.name = "Teleport to waypoint";
        waypoint.detail = "Go to the waypoint set on your map.";
        ArrayPush(this.m_rows, waypoint);
        let me = new MpAdminRow();
        me.kind = "self";
        me.name = "Heal myself";
        me.detail = "Full health, and back up if you're down.";
        ArrayPush(this.m_rows, me);

        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            if ArraySize(f) >= 5 && Equals(f[0], "P") {
                let p = new MpAdminRow();
                p.kind = "player";
                p.name = f[1];
                p.detail = StrLen(f[2]) > 0 ? "Discord: " + f[2] : "";
                p.isAdmin = Equals(f[3], "1");
                p.isMe = Equals(f[4], "1");
                ArrayPush(this.m_rows, p);
            }
        }
        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            if ArraySize(f) >= 5 && Equals(f[0], "L") {
                let l = new MpAdminRow();
                l.kind = "place";
                l.name = f[1];
                l.position = new Vector4(StringToFloat(f[2]), StringToFloat(f[3]), StringToFloat(f[4]), 1.0);
                l.detail = "Saved place.";
                ArrayPush(this.m_rows, l);
            }
        }
        if this.m_selected >= ArraySize(this.m_rows) {
            this.m_selected = 0;
        }
        this.m_armed = "";
        if !this.m_open {
            let controller = GameInstance.GetNetworkWorldSystem().GetAppearanceSystem().m_controller;
            if IsDefined(controller) {
                controller.OpenAdminPanel();
            }
        } else {
            this.Redraw();
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

    private func Selected() -> ref<MpAdminRow> {
        return this.m_selected >= 0 && this.m_selected < ArraySize(this.m_rows) ? this.m_rows[this.m_selected] : null;
    }

    private func ActionsFor(row: ref<MpAdminRow>) -> array<String> {
        let a: array<String>;
        if !IsDefined(row) {
            return a;
        }
        if Equals(row.kind, "waypoint") {
            ArrayPush(a, "waypoint");
        }
        if Equals(row.kind, "self") {
            ArrayPush(a, "healself");
        }
        if Equals(row.kind, "place") {
            ArrayPush(a, "goplace");
            ArrayPush(a, "removeplace");
        }
        if Equals(row.kind, "player") {
            if !row.isMe {
                ArrayPush(a, "goto");
                ArrayPush(a, "bring");
            }
            ArrayPush(a, "heal");
            if !row.isMe {
                ArrayPush(a, "kick");
                ArrayPush(a, "ban");
                ArrayPush(a, row.isAdmin ? "unadmin" : "admin");
            }
        }
        return a;
    }

    private func Label(action: String) -> String {
        if Equals(this.m_armed, action) {
            return "PRESS ENTER AGAIN TO CONFIRM";
        }
        switch action {
            case "waypoint": return "TELEPORT";
            case "healself": return "HEAL";
            case "goplace": return "TELEPORT HERE";
            case "removeplace": return "DELETE PLACE";
            case "goto": return "TELEPORT TO";
            case "bring": return "BRING TO ME";
            case "heal": return "HEAL / REVIVE";
            case "kick": return "KICK";
            case "ban": return "BAN";
            case "admin": return "MAKE ADMIN";
            case "unadmin": return "REMOVE ADMIN";
        }
        return action;
    }

    private func NeedsConfirm(action: String) -> Bool {
        return Equals(action, "kick") || Equals(action, "ban") || Equals(action, "unadmin") || Equals(action, "removeplace") || Equals(action, "admin");
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
            case "waypoint":
                MpTeleportToWaypoint();
                this.Close();
                return;
            case "healself":
                MpHealSelf();
                MpJobMessage("Healed.");
                break;
            case "goplace":
                AdminServer.TeleportSelf(row.position.X, row.position.Y, row.position.Z);
                this.Close();
                return;
            case "removeplace":
                AdminServer.RemovePlace(row.name);
                break;
            case "goto":
                AdminServer.GoTo(row.name);
                this.Close();
                return;
            case "bring":
                AdminServer.Bring(row.name);
                break;
            case "heal":
                AdminServer.Heal(row.name);
                break;
            case "kick":
                AdminServer.Kick(row.name, "");
                AdminServer.OpenPanel();
                break;
            case "ban":
                AdminServer.Ban(row.name, "");
                AdminServer.OpenPanel();
                break;
            case "admin":
                AdminServer.SetAdmin(row.name, true);
                break;
            case "unadmin":
                AdminServer.SetAdmin(row.name, false);
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
            canvas.SetName(n"mp_admin_panel");
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
        MpJbRect(c, x, y, w, 3.0, MpJbGold(), 1.0);
        MpJbRect(c, x, y, 3.0, h, MpJbRedDim(), 1.0);
        MpJbText(c, x + 40.0, y + 28.0, "ADMIN", 54, n"Bold", MpJbGold());
        MpJbText(c, x + 240.0, y + 50.0, "Add a teleport place: stand there and type /addplace Name in chat", 22, n"Regular", MpJbInkDim());
        MpJbRect(c, x + 40.0, y + 108.0, w - 80.0, 1.0, MpJbRedDim(), 1.0);

        // List.
        let lx = x + 40.0;
        let ly = y + 128.0;
        let i = 0;
        let lastKind = "";
        let first = Max(0, this.m_selected - 11);
        for row in this.m_rows {
            if i >= first && ly < y + h - 90.0 {
                if NotEquals(row.kind, lastKind) && (Equals(row.kind, "player") || Equals(row.kind, "place")) {
                    ly += 6.0;
                    MpJbText(c, lx, ly, Equals(row.kind, "player") ? "PLAYERS" : "PLACES", 20, n"Bold", MpJbInkFaint());
                    ly += 30.0;
                }
                let selected = i == this.m_selected;
                if selected {
                    MpJbRect(c, lx - 10.0, ly - 4.0, 470.0, 46.0, MpJbRed(), this.m_focus == 0 ? 0.22 : 0.10);
                    MpJbRect(c, lx - 10.0, ly - 4.0, 4.0, 46.0, MpJbRed(), 1.0);
                }
                MpJbText(c, lx + 6.0, ly + 2.0, row.name, 28, Equals(row.kind, "player") ? n"Bold" : n"Medium", selected ? MpJbInk() : MpJbInkDim());
                if row.isAdmin {
                    MpJbText(c, lx + 360.0, ly + 8.0, "ADMIN", 18, n"Bold", MpJbGold());
                }
                if row.isMe {
                    MpJbText(c, lx + 300.0, ly + 8.0, "YOU", 18, n"Bold", MpJbCyan());
                }
                ly += 48.0;
            }
            lastKind = row.kind;
            i += 1;
        }

        // Details and buttons.
        MpJbRect(c, x + 540.0, y + 128.0, 1.0, h - 200.0, MpJbRedDim(), 1.0);
        let row = this.Selected();
        if IsDefined(row) {
            let dx = x + 580.0;
            MpJbText(c, dx, y + 130.0, StrUpper(row.name), 48, n"Bold", MpJbInk());
            MpJbText(c, dx, y + 196.0, row.detail, 24, n"Regular", MpJbInkDim());
            let by = y + 260.0;
            let a = 0;
            for action in this.ActionsFor(row) {
                let focused = this.m_focus == 1 && a == this.m_action;
                let danger = Equals(action, "kick") || Equals(action, "ban") || Equals(action, "removeplace");
                MpJbRect(c, dx, by, 520.0, 48.0, danger ? MpJbRed() : MpJbRedDim(), focused ? 1.0 : 0.5);
                if focused {
                    MpJbRect(c, dx + 520.0, by, 8.0, 48.0, MpJbGold(), 1.0);
                }
                MpJbText(c, dx + 18.0, by + 9.0, this.Label(action), 26, n"Bold", focused ? MpJbPlate() : MpJbInk());
                by += 58.0;
                a += 1;
            }
        }
        MpJbText(c, x + 40.0, y + h - 46.0, "UP / DOWN  choose        RIGHT  buttons        ENTER  select        ESC  close", 22, n"Medium", MpJbInkFaint());
    }
}
