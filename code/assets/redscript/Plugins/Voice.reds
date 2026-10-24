module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Ink.*

// Proximity voice chat. The sound itself is handled by the mod's own code
// (microphone, Opus, positional playback); this is the player's side of it:
//   - hold the voice key (N by default) to talk,
//   - the range key (F11 by default) cycles whisper / normal / shout,
//   - a small marker at the bottom of the screen shows when you're on air.
// Typing in chat or having a menu open never sends your voice.

public class MpVoice extends ScriptableSystem {
    private let m_canvas: ref<inkCanvas>;
    private let m_talking: Bool;

    public static func Get() -> ref<MpVoice> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpVoice") as MpVoice;
    }

    public func Talk(on: Bool) -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(world) || !world.IsConnected() {
            return;
        }
        if on && MpChatIsOpen() {
            on = false;
        }
        if on && !world.HasVoiceMicrophone() {
            MpJobMessage("No microphone found. Check Windows Settings > Privacy > Microphone, then rejoin.");
            return;
        }
        if Equals(this.m_talking, on) {
            return;
        }
        this.m_talking = on;
        world.SetVoiceTalking(on);
        this.Draw();
    }

    public func CycleRange() -> Void {
        let world = GameInstance.GetNetworkWorldSystem();
        if !IsDefined(world) || !world.IsConnected() {
            return;
        }
        let next = (world.GetVoiceRange() + 1) % 3;
        world.SetVoiceRange(next);
        MpJobMessage("Voice: " + MpVoiceRangeName(next) + " (" + MpVoiceRangeMeters(next) + ")");
        this.Draw();
    }

    // Shown only while talking.
    private func Draw() -> Void {
        let controller = GameInstance.GetNetworkWorldSystem().GetAppearanceSystem().m_controller;
        if !IsDefined(controller) {
            return;
        }
        let root = controller.GetRootCompoundWidget();
        if !IsDefined(root) {
            return;
        }
        if !this.m_talking {
            if IsDefined(this.m_canvas) {
                root.RemoveChild(this.m_canvas);
                this.m_canvas = null;
            }
            return;
        }
        if !IsDefined(this.m_canvas) {
            let canvas = new inkCanvas();
            canvas.SetName(n"mp_voice");
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

        let range = GameInstance.GetNetworkWorldSystem().GetVoiceRange();
        let x = 860.0;
        let y = 980.0;
        MpJbRect(this.m_canvas, x, y, 200.0, 40.0, MpJbPlate(), 0.85);
        MpJbRect(this.m_canvas, x, y, 4.0, 40.0, MpJbCyan(), 1.0);
        MpJbRect(this.m_canvas, x + 18.0, y + 14.0, 12.0, 12.0, MpJbCyan(), 1.0);
        MpJbText(this.m_canvas, x + 42.0, y + 7.0, "ON AIR  " + StrUpper(MpVoiceRangeName(range)), 22, n"Bold", MpJbInk());
    }
}

public func MpVoiceRangeName(range: Int32) -> String {
    switch range {
        case 0: return "Whisper";
        case 2: return "Shout";
    }
    return "Normal";
}

public func MpVoiceRangeMeters(range: Int32) -> String {
    switch range {
        case 0: return "3 m";
        case 2: return "40 m";
    }
    return "15 m";
}

public func MpChatIsOpen() -> Bool {
    let bb = GameInstance.GetBlackboardSystem(GetGameInstance()).Get(GetAllBlackboardDefs().UIGameData);
    return IsDefined(bb) && bb.GetBool(GetAllBlackboardDefs().UIGameData.UIChatInputContextRequest);
}
