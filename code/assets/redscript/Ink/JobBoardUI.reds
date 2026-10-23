module CyberpunkMP.Ink

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Plugins.*

// The job board: what you see when you press the job key.
//
// Left: every job, with your level in it and whether you're on duty, then the
// services you can call (mechanic, Trauma Team, NCPD, a taxi). Right: the
// selected job's details, your XP towards the next level, and what you can do.
// "View contracts" swaps the right side for the contracts on offer.
//
// Built in code rather than from an .inkwidget, laid out on a 1920x1080 sheet
// and scaled to the screen. The server sends the data (JobBoard.cs).
//
// Keys: up/down choose, right/left move between the list and the buttons,
// Enter does it, Esc goes back or closes.

public class MpJobEntry {
    public let id: String;
    public let name: String;
    public let category: String;
    public let description: String;
    public let pay: String;
    public let level: Int32;
    public let xp: Int32;
    public let levelStart: Int32;
    public let levelNext: Int32;
    public let onDuty: Bool;
    public let serviceId: String;
    public let serviceLabel: String;
    public let serviceDescription: String;
    public let openCalls: Int32;
}

public class MpContractEntry {
    public let id: Uint32;
    public let title: String;
    public let detail: String;
    public let reward: Int32;
    public let distance: Int32;
    public let playerCall: Bool;
    public let lockedUntil: Int32;
}

// One row of the left-hand list: a job, or a service to call.
public class MpJobRow {
    public let job: ref<MpJobEntry>;
    public let isService: Bool;
    public let serviceId: String;
    public let label: String;
    public let description: String;
}

public func MpJbRed() -> HDRColor = new HDRColor(1.0, 0.33, 0.30, 1.0)
public func MpJbRedDim() -> HDRColor = new HDRColor(0.45, 0.13, 0.13, 1.0)
public func MpJbCyan() -> HDRColor = new HDRColor(0.37, 0.96, 1.0, 1.0)
public func MpJbGold() -> HDRColor = new HDRColor(1.0, 0.84, 0.25, 1.0)
public func MpJbInk() -> HDRColor = new HDRColor(0.93, 0.94, 0.95, 1.0)
public func MpJbInkDim() -> HDRColor = new HDRColor(0.60, 0.63, 0.67, 1.0)
public func MpJbInkFaint() -> HDRColor = new HDRColor(0.36, 0.39, 0.43, 1.0)
public func MpJbPlate() -> HDRColor = new HDRColor(0.035, 0.03, 0.05, 1.0)
public func MpJbFont() -> String = "base\\gameplay\\gui\\fonts\\raj\\raj.inkfontfamily"

public func MpJbRect(parent: ref<inkCompoundWidget>, x: Float, y: Float, w: Float, h: Float, color: HDRColor, opacity: Float) -> ref<inkRectangle> {
    let r = new inkRectangle();
    r.SetAnchor(inkEAnchor.TopLeft);
    r.SetAnchorPoint(new Vector2(0.0, 0.0));
    r.SetMargin(new inkMargin(x, y, 0.0, 0.0));
    r.SetSize(new Vector2(w, h));
    r.SetTintColor(color);
    r.SetOpacity(opacity);
    r.Reparent(parent);
    return r;
}

public func MpJbText(parent: ref<inkCompoundWidget>, x: Float, y: Float, text: String, size: Int32, style: CName, color: HDRColor) -> ref<inkText> {
    let t = new inkText();
    t.SetAnchor(inkEAnchor.TopLeft);
    t.SetAnchorPoint(new Vector2(0.0, 0.0));
    t.SetMargin(new inkMargin(x, y, 0.0, 0.0));
    t.SetFontFamily(MpJbFont());
    t.SetFontStyle(style);
    t.SetFontSize(size);
    t.SetText(text);
    t.SetTintColor(color);
    t.Reparent(parent);
    return t;
}

public func MpJbWrapped(parent: ref<inkCompoundWidget>, x: Float, y: Float, width: Float, text: String, size: Int32, color: HDRColor) -> ref<inkText> {
    let t = MpJbText(parent, x, y, text, size, n"Regular", color);
    t.SetWrapping(true, width);
    t.SetSize(new Vector2(width, 200.0));
    return t;
}

public func MpJbField(fields: array<String>, index: Int32) -> String {
    return index < ArraySize(fields) ? fields[index] : "";
}

public func MpJbDistance(meters: Int32) -> String {
    if meters >= 1000 {
        let km = Cast<Float>(meters) / 1000.0;
        return FloatToStringPrec(km, 1) + " km";
    }
    return IntToString(meters) + " m";
}

public class MpJobBoard extends ScriptableSystem {
    private let m_controller: wref<MultiplayerGameController>;
    private let m_canvas: ref<inkCanvas>;
    private let m_open: Bool;
    // 0 = jobs, 1 = contracts
    private let m_mode: Int32;
    private let m_loading: Bool;

    private let m_jobs: array<ref<MpJobEntry>>;
    private let m_rows: array<ref<MpJobRow>>;
    private let m_onDuty: String;
    private let m_activeTitle: String;
    private let m_activeStage: String;
    private let m_selected: Int32;
    // 0 = the list, 1 = the buttons on the right
    private let m_focus: Int32;
    private let m_action: Int32;

    private let m_contracts: array<ref<MpContractEntry>>;
    private let m_contractsJob: String;
    private let m_contractSelected: Int32;

    public static func Get() -> ref<MpJobBoard> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Ink.MpJobBoard") as MpJobBoard;
    }

    public func IsOpen() -> Bool {
        return this.m_open;
    }

    public func Open(controller: ref<MultiplayerGameController>) -> Void {
        this.m_controller = controller;
        this.m_open = true;
        this.m_mode = 0;
        this.m_focus = 0;
        this.m_action = 0;
        this.m_loading = true;
        this.Redraw();
        JobBoardServer.OpenBoard();
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

    // ------------------------------------------------------------ data from the server

    public func OnBoardData(payload: String) -> Void {
        ArrayClear(this.m_jobs);
        ArrayClear(this.m_rows);
        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            let kind = MpJbField(f, 0);
            if Equals(kind, "H") {
                this.m_onDuty = MpJbField(f, 1);
                this.m_activeTitle = MpJbField(f, 2);
                this.m_activeStage = MpJbField(f, 3);
            } else {
                if Equals(kind, "J") {
                    let job = new MpJobEntry();
                    job.id = MpJbField(f, 1);
                    job.name = MpJbField(f, 2);
                    job.category = MpJbField(f, 3);
                    job.description = MpJbField(f, 4);
                    job.pay = MpJbField(f, 5);
                    job.level = StringToInt(MpJbField(f, 6));
                    job.xp = StringToInt(MpJbField(f, 7));
                    job.levelStart = StringToInt(MpJbField(f, 8));
                    job.levelNext = StringToInt(MpJbField(f, 9));
                    job.onDuty = Equals(MpJbField(f, 10), "1");
                    job.serviceId = MpJbField(f, 11);
                    job.serviceLabel = MpJbField(f, 12);
                    job.serviceDescription = MpJbField(f, 13);
                    job.openCalls = StringToInt(MpJbField(f, 14));
                    ArrayPush(this.m_jobs, job);

                    let row = new MpJobRow();
                    row.job = job;
                    row.label = job.name;
                    ArrayPush(this.m_rows, row);
                }
            }
        }

        // Services after the jobs.
        for job in this.m_jobs {
            if StrLen(job.serviceId) > 0 {
                let service = new MpJobRow();
                service.isService = true;
                service.serviceId = job.serviceId;
                service.label = job.serviceLabel;
                service.description = job.serviceDescription;
                ArrayPush(this.m_rows, service);
            }
        }
        let taxi = new MpJobRow();
        taxi.isService = true;
        taxi.serviceId = "taxi";
        taxi.label = "Call a taxi";
        taxi.description = "Set a waypoint on your map first: a player on duty as Taxi Driver picks you up and drives you there. The fare is 100 eddies.";
        ArrayPush(this.m_rows, taxi);

        if this.m_selected >= ArraySize(this.m_rows) {
            this.m_selected = 0;
        }
        this.m_loading = false;
        this.m_mode = 0;
        this.m_action = 0;
        if this.m_open {
            this.Redraw();
        }
    }

    public func OnContractsData(payload: String) -> Void {
        ArrayClear(this.m_contracts);
        for record in StrSplit(payload, "^") {
            let f = StrSplit(record, "~");
            let kind = MpJbField(f, 0);
            if Equals(kind, "H") {
                this.m_contractsJob = MpJbField(f, 2);
            } else {
                if Equals(kind, "C") {
                    let c = new MpContractEntry();
                    c.id = Cast<Uint32>(StringToInt(MpJbField(f, 1)));
                    c.title = MpJbField(f, 2);
                    c.detail = MpJbField(f, 3);
                    c.reward = StringToInt(MpJbField(f, 4));
                    c.distance = StringToInt(MpJbField(f, 5));
                    c.playerCall = Equals(MpJbField(f, 6), "1");
                    c.lockedUntil = StringToInt(MpJbField(f, 7));
                    ArrayPush(this.m_contracts, c);
                }
            }
        }
        this.m_contractSelected = 0;
        this.m_loading = false;
        this.m_mode = 1;
        if this.m_open {
            this.Redraw();
        }
    }

    // ------------------------------------------------------------ input

    // Returns true when the board used the key.
    public func HandleAction(name: CName, pressed: Bool) -> Bool {
        if !this.m_open || !pressed {
            return this.m_open;
        }
        if Equals(name, n"UIJob") {
            this.Close();
            return true;
        }
        if Equals(name, n"cancel") {
            if this.m_mode == 1 {
                this.m_loading = true;
                this.Redraw();
                JobBoardServer.OpenBoard();
            } else {
                this.Close();
            }
            return true;
        }
        if this.m_loading {
            return true;
        }

        let up = Equals(name, n"popup_moveUp") || Equals(name, n"popup_moveUp_left_stick_up");
        let down = Equals(name, n"popup_moveDown") || Equals(name, n"popup_moveUp_left_stick_down");
        let left = Equals(name, n"popup_moveLeft") || Equals(name, n"popup_prior");
        let right = Equals(name, n"popup_moveRight") || Equals(name, n"popup_next");
        let proceed = Equals(name, n"proceed");

        if this.m_mode == 1 {
            let count = ArraySize(this.m_contracts);
            if up && count > 0 {
                this.m_contractSelected = (this.m_contractSelected + count - 1) % count;
            }
            if down && count > 0 {
                this.m_contractSelected = (this.m_contractSelected + 1) % count;
            }
            if left {
                this.m_loading = true;
                JobBoardServer.OpenBoard();
            }
            if proceed && count > 0 {
                let c = this.m_contracts[this.m_contractSelected];
                if c.lockedUntil > 0 {
                    MpJobMessage("Unlocks at level " + IntToString(c.lockedUntil) + ".");
                } else {
                    JobBoardServer.AcceptContract(c.id);
                    this.Close();
                    return true;
                }
            }
            this.Redraw();
            return true;
        }

        let rows = ArraySize(this.m_rows);
        let actions = this.ActionsFor(this.SelectedRow());
        if this.m_focus == 0 {
            if up && rows > 0 {
                this.m_selected = (this.m_selected + rows - 1) % rows;
                this.m_action = 0;
            }
            if down && rows > 0 {
                this.m_selected = (this.m_selected + 1) % rows;
                this.m_action = 0;
            }
            if right && ArraySize(actions) > 0 {
                this.m_focus = 1;
            }
            if proceed && ArraySize(actions) > 0 {
                this.Run(actions[0]);
                return true;
            }
        } else {
            let n = ArraySize(actions);
            if up && n > 0 {
                this.m_action = (this.m_action + n - 1) % n;
            }
            if down && n > 0 {
                this.m_action = (this.m_action + 1) % n;
            }
            if left {
                this.m_focus = 0;
            }
            if proceed && this.m_action < n {
                this.Run(actions[this.m_action]);
                return true;
            }
        }
        this.Redraw();
        return true;
    }

    private func SelectedRow() -> ref<MpJobRow> {
        if this.m_selected >= 0 && this.m_selected < ArraySize(this.m_rows) {
            return this.m_rows[this.m_selected];
        }
        return null;
    }

    // The buttons for a row, as action names.
    private func ActionsFor(row: ref<MpJobRow>) -> array<String> {
        let actions: array<String>;
        if !IsDefined(row) {
            return actions;
        }
        if row.isService {
            ArrayPush(actions, "call");
            return actions;
        }
        if row.job.onDuty {
            ArrayPush(actions, "contracts");
            if StrLen(this.m_activeTitle) > 0 {
                ArrayPush(actions, "cancel");
            }
            ArrayPush(actions, "offduty");
        } else {
            ArrayPush(actions, "onduty");
        }
        return actions;
    }

    private func ActionLabel(action: String, row: ref<MpJobRow>) -> String {
        if Equals(action, "call") {
            return Equals(row.serviceId, "taxi") ? "REQUEST A RIDE" : "CALL NOW";
        }
        if Equals(action, "contracts") {
            return Equals(row.job.id, "taxi") ? "VIEW RIDE REQUESTS" : "VIEW CONTRACTS";
        }
        if Equals(action, "cancel") {
            return "CANCEL CURRENT CONTRACT";
        }
        if Equals(action, "offduty") {
            return "GO OFF DUTY";
        }
        return "GO ON DUTY";
    }

    private func Run(action: String) -> Void {
        let row = this.SelectedRow();
        if !IsDefined(row) {
            return;
        }
        if Equals(action, "call") {
            if Equals(row.serviceId, "taxi") {
                MpRequestTaxiToWaypoint();
            } else {
                JobBoardServer.CallService(row.serviceId);
            }
            this.Close();
            return;
        }
        if Equals(action, "cancel") {
            JobBoardServer.CancelContract();
            this.Close();
            return;
        }
        this.m_loading = true;
        this.m_focus = 0;
        this.Redraw();
        if Equals(action, "contracts") {
            JobBoardServer.OpenContracts();
        } else {
            if Equals(action, "offduty") {
                JobBoardServer.GoOffDuty();
            } else {
                JobBoardServer.GoOnDuty(row.job.id);
            }
        }
    }

    // ------------------------------------------------------------ drawing

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
            canvas.SetName(n"mp_job_board");
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
        this.m_canvas.SetScale(new Vector2(scale, scale));
        this.m_canvas.RemoveAllChildren();

        let c = this.m_canvas;
        let x = 250.0;
        let y = 130.0;
        let w = 1420.0;
        let h = 820.0;

        // Frame.
        MpJbRect(c, x, y, w, h, MpJbPlate(), 0.94);
        MpJbRect(c, x, y, w, 3.0, MpJbRed(), 1.0);
        MpJbRect(c, x, y + h - 2.0, w, 2.0, MpJbRedDim(), 1.0);
        MpJbRect(c, x, y, 3.0, h, MpJbRedDim(), 1.0);
        MpJbRect(c, x + w - 40.0, y + 3.0, 40.0, 6.0, MpJbGold(), 1.0);

        MpJbText(c, x + 40.0, y + 28.0, "JOB BOARD", 54, n"Bold", MpJbRed());
        let status = StrLen(this.m_onDuty) > 0 ? "ON DUTY: " + StrUpper(this.DutyName()) : "OFF DUTY";
        MpJbText(c, x + 340.0, y + 50.0, status, 26, n"Medium", StrLen(this.m_onDuty) > 0 ? MpJbCyan() : MpJbInkDim());
        if StrLen(this.m_activeTitle) > 0 {
            MpJbText(c, x + 760.0, y + 50.0, "CURRENT: " + StrUpper(this.m_activeTitle) + " - " + this.m_activeStage, 22, n"Regular", MpJbGold());
        }
        MpJbRect(c, x + 40.0, y + 108.0, w - 80.0, 1.0, MpJbRedDim(), 1.0);

        if this.m_loading {
            MpJbText(c, x + 40.0, y + 140.0, "CONNECTING TO THE BOARD...", 30, n"Medium", MpJbInkDim());
        } else {
            if this.m_mode == 1 {
                this.DrawContracts(c, x, y, w, h);
            } else {
                this.DrawJobs(c, x, y, w, h);
            }
        }

        let hints = this.m_mode == 1
            ? "UP / DOWN  choose        ENTER  accept        LEFT / ESC  back to jobs"
            : "UP / DOWN  choose        RIGHT  buttons        ENTER  select        ESC  close";
        MpJbText(c, x + 40.0, y + h - 46.0, hints, 22, n"Medium", MpJbInkFaint());
    }

    private func DutyName() -> String {
        for job in this.m_jobs {
            if Equals(job.id, this.m_onDuty) {
                return job.name;
            }
        }
        return this.m_onDuty;
    }

    private func DrawJobs(c: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float) -> Void {
        // Left: the list.
        let listX = x + 40.0;
        let rowY = y + 130.0;
        let servicesHeader = false;
        let i = 0;
        for row in this.m_rows {
            if row.isService && !servicesHeader {
                servicesHeader = true;
                rowY += 10.0;
                MpJbText(c, listX, rowY, "SERVICES", 20, n"Bold", MpJbInkFaint());
                rowY += 30.0;
            }
            let selected = i == this.m_selected;
            let rowH = row.isService ? 40.0 : 52.0;
            if selected {
                MpJbRect(c, listX - 10.0, rowY - 4.0, 470.0, rowH, MpJbRed(), this.m_focus == 0 ? 0.22 : 0.10);
                MpJbRect(c, listX - 10.0, rowY - 4.0, 4.0, rowH, MpJbRed(), 1.0);
            }
            let color = selected ? MpJbInk() : MpJbInkDim();
            if row.isService {
                MpJbText(c, listX + 6.0, rowY + 2.0, row.label, 26, n"Medium", color);
            } else {
                MpJbText(c, listX + 6.0, rowY, StrUpper(row.job.name), 30, n"Bold", color);
                MpJbText(c, listX + 300.0, rowY + 8.0, "LVL " + IntToString(row.job.level), 20, n"Medium", MpJbGold());
                if row.job.onDuty {
                    MpJbText(c, listX + 375.0, rowY + 8.0, "ON DUTY", 20, n"Bold", MpJbCyan());
                } else {
                    if row.job.openCalls > 0 {
                        MpJbText(c, listX + 375.0, rowY + 8.0, IntToString(row.job.openCalls) + " CALL" + (row.job.openCalls > 1 ? "S" : ""), 20, n"Bold", MpJbRed());
                    }
                }
            }
            rowY += rowH;
            i += 1;
        }

        // Right: details.
        MpJbRect(c, x + 540.0, y + 128.0, 1.0, h - 200.0, MpJbRedDim(), 1.0);
        let dx = x + 580.0;
        let dy = y + 130.0;
        let row = this.SelectedRow();
        if !IsDefined(row) {
            return;
        }
        if row.isService {
            MpJbText(c, dx, dy, StrUpper(row.label), 44, n"Bold", MpJbInk());
            MpJbWrapped(c, dx, dy + 70.0, 760.0, row.description, 26, MpJbInkDim());
        } else {
            let job = row.job;
            MpJbText(c, dx, dy, StrUpper(job.category), 22, n"Medium", MpJbRed());
            MpJbText(c, dx, dy + 26.0, StrUpper(job.name), 52, n"Bold", MpJbInk());
            MpJbWrapped(c, dx, dy + 100.0, 760.0, job.description, 25, MpJbInkDim());

            MpJbText(c, dx, dy + 250.0, "PAY", 20, n"Bold", MpJbInkFaint());
            MpJbText(c, dx, dy + 274.0, job.pay, 28, n"Medium", MpJbGold());

            // Level and XP bar.
            MpJbText(c, dx, dy + 330.0, "LEVEL " + IntToString(job.level), 30, n"Bold", MpJbInk());
            let span = job.levelNext - job.levelStart;
            let into = job.xp - job.levelStart;
            let fill = span > 0 ? Cast<Float>(into) / Cast<Float>(span) : 1.0;
            fill = MaxF(0.0, MinF(1.0, fill));
            MpJbRect(c, dx, dy + 374.0, 520.0, 10.0, MpJbInkFaint(), 0.35);
            MpJbRect(c, dx, dy + 374.0, 520.0 * fill, 10.0, MpJbCyan(), 1.0);
            let xpText = span > 0 ? IntToString(into) + " / " + IntToString(span) + " XP to level " + IntToString(job.level + 1) : "Max level";
            MpJbText(c, dx + 540.0, dy + 364.0, xpText, 20, n"Medium", MpJbInkDim());
            MpJbText(c, dx, dy + 394.0, "Higher levels pay more and unlock better contracts.", 20, n"Regular", MpJbInkFaint());
        }

        // Buttons.
        let actions = this.ActionsFor(row);
        let by = y + h - 210.0;
        let a = 0;
        for action in actions {
            let focused = this.m_focus == 1 && a == this.m_action;
            let primary = a == 0;
            MpJbRect(c, dx, by, 420.0, 46.0, primary ? MpJbRed() : MpJbRedDim(), focused ? 1.0 : (primary ? 0.55 : 0.45));
            if focused {
                MpJbRect(c, dx + 420.0, by, 8.0, 46.0, MpJbGold(), 1.0);
            }
            MpJbText(c, dx + 18.0, by + 8.0, this.ActionLabel(action, row), 26, n"Bold", focused ? MpJbPlate() : MpJbInk());
            by += 56.0;
            a += 1;
        }
    }

    private func DrawContracts(c: ref<inkCanvas>, x: Float, y: Float, w: Float, h: Float) -> Void {
        let lx = x + 40.0;
        let ly = y + 130.0;
        MpJbText(c, lx, ly, StrUpper(this.m_contractsJob) + " - CONTRACTS", 34, n"Bold", MpJbInk());
        ly += 56.0;

        if ArraySize(this.m_contracts) == 0 {
            MpJbText(c, lx, ly, "Nothing on offer right now. Check back in a minute.", 26, n"Regular", MpJbInkDim());
            return;
        }

        // Header row.
        MpJbText(c, lx + 900.0, ly, "DISTANCE", 18, n"Bold", MpJbInkFaint());
        MpJbText(c, lx + 1100.0, ly, "PAY", 18, n"Bold", MpJbInkFaint());
        ly += 28.0;

        let i = 0;
        for contract in this.m_contracts {
            let selected = i == this.m_contractSelected;
            let locked = contract.lockedUntil > 0;
            if selected {
                MpJbRect(c, lx - 10.0, ly - 4.0, w - 60.0, 70.0, MpJbRed(), 0.20);
                MpJbRect(c, lx - 10.0, ly - 4.0, 4.0, 70.0, MpJbRed(), 1.0);
            }
            let titleColor = locked ? MpJbInkFaint() : (selected ? MpJbInk() : MpJbInkDim());
            let tag = "";
            if contract.playerCall {
                tag = "PLAYER  ";
            }
            MpJbText(c, lx + 6.0, ly, tag + StrUpper(contract.title), 28, n"Bold", contract.playerCall ? MpJbCyan() : titleColor);
            let detail = locked ? "Unlocks at level " + IntToString(contract.lockedUntil) + ". " + contract.detail : contract.detail;
            MpJbText(c, lx + 6.0, ly + 34.0, detail, 20, n"Regular", locked ? MpJbInkFaint() : MpJbInkDim());
            if !locked && contract.distance > 0 {
                MpJbText(c, lx + 900.0, ly + 6.0, MpJbDistance(contract.distance), 26, n"Medium", titleColor);
            }
            MpJbText(c, lx + 1100.0, ly + 6.0, IntToString(contract.reward) + " EDDIES", 26, n"Bold", locked ? MpJbInkFaint() : MpJbGold());
            ly += 78.0;
            i += 1;
            if ly > y + h - 120.0 {
                return;
            }
        }
    }
}

// "Call a taxi": to the waypoint on the player's map.
public func MpRequestTaxiToWaypoint() -> Void {
    let mappins: array<ref<IMappin>>;
    GameInstance.GetMappinSystem(GetGameInstance()).GetMappins(gamemappinsMappinTargetType.Map, mappins);
    for mappin in mappins {
        if IsDefined(mappin) && Equals(mappin.GetVariant(), gamedataMappinVariant.CustomPositionVariant) {
            TaxiServer.CreateJob(mappin.GetWorldPosition());
            MpJobMessage("Ride requested. A taxi driver on duty will pick you up here.");
            return;
        }
    }
    MpJobMessage("Set a waypoint on your map first, then request a ride.");
}
