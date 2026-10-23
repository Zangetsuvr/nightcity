module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*
import CyberpunkMP.Ink.*

// The players' phone (Ink/PhoneUI.reds). On the server the phone key opens this
// instead of the game's own phone: contacts you swap in person, texts, location
// pings. The server keeps all of it (CharacterSystem/Phone.cs).

public native class PhoneServer extends ServerRpc {
    public static native func OpenPhone() -> Void;
    public static native func ShareContact(character: String) -> Void;
    public static native func AnswerRequest(character: String, accept: Bool) -> Void;
    public static native func SendText(character: String, message: String) -> Void;
    public static native func PingLocation(character: String) -> Void;
    public static native func RemoveContact(character: String) -> Void;
    public static native func SetBlocked(character: String, blocked: Bool) -> Void;
}

public class PhoneClient extends ClientRpc {
    public func ShowPhone(payload: String) -> Void {
        let phone = MpPhone.Get();
        if IsDefined(phone) {
            phone.OnData(payload);
        }
    }

    public func ReceiveText(from: String, message: String) -> Void {
        MpPhoneIncoming(from, message);
    }

    public func ReceivePing(from: String, x: Float, y: Float, z: Float) -> Void {
        let pings = MpPhonePings.Get();
        if IsDefined(pings) {
            pings.Add(new Vector4(x, y, z, 1.0));
        }
        MpJobMessage(from + " sent you their location. It's on your map.");
        GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_phone_sms");
    }

    public func Notice(message: String) -> Void {
        MpJobMessage(message);
    }
}

// A text arrived: into chat, a pop-up, and remembered for /r.
public func MpPhoneIncoming(from: String, message: String) -> Void {
    let phone = MpPhone.Get();
    if IsDefined(phone) {
        phone.SetLastSender(from);
    }
    let evt = new ChatMessageUIEvent();
    evt.author = "TEXT from " + from;
    evt.message = message;
    GameInstance.GetUISystem(GetGameInstance()).QueueEvent(evt);
    MpJobMessage("Text from " + from + "  (reply: /r message)");
    GameInstance.GetAudioSystem(GetGameInstance()).Play(n"ui_phone_sms");
}

// On the server the phone key opens the players' phone.
@wrapMethod(PhoneSystem)
private final func OnUsePhone(request: ref<UsePhoneRequest>) -> Void {
    let network = GameInstance.GetNetworkWorldSystem();
    if IsDefined(network) && network.IsConnected() {
        let phone = MpPhone.Get();
        if IsDefined(phone) {
            phone.RequestOpen();
        }
        return;
    }
    wrappedMethod(request);
}

// Location pings on the map, gone after a few minutes.
public class MpPhonePings extends ScriptableSystem {
    private let m_pins: array<NewMappinID>;
    private let m_generation: Int32;

    public static func Get() -> ref<MpPhonePings> {
        return GameInstance.GetScriptableSystemsContainer(GetGameInstance()).Get(n"CyberpunkMP.Plugins.MpPhonePings") as MpPhonePings;
    }

    public func Add(position: Vector4) -> Void {
        // One ping at a time: a new one replaces the last.
        this.Clear();
        let data: MappinData;
        data.mappinType = t"Mappins.QuestStaticMappinDefinition";
        data.variant = gamedataMappinVariant.FastTravelVariant;
        data.active = true;
        data.visibleThroughWalls = true;
        let id = GameInstance.GetMappinSystem(this.GetGameInstance()).RegisterMappin(data, position);
        ArrayPush(this.m_pins, id);
        this.m_generation += 1;
        let expire = new MpPhonePingExpire();
        expire.generation = this.m_generation;
        GameInstance.GetDelaySystem(this.GetGameInstance()).DelayCallback(expire, 300.0, false);
    }

    public func Expire(generation: Int32) -> Void {
        if generation == this.m_generation {
            this.Clear();
        }
    }

    public func Clear() -> Void {
        for id in this.m_pins {
            GameInstance.GetMappinSystem(this.GetGameInstance()).UnregisterMappin(id);
        }
        ArrayClear(this.m_pins);
    }
}

public class MpPhonePingExpire extends DelayCallback {
    public let generation: Int32;

    public func Call() -> Void {
        let pings = MpPhonePings.Get();
        if IsDefined(pings) {
            pings.Expire(this.generation);
        }
    }
}

// Ask the chat box to open with some text already typed (for replying).
public class MpOpenChatEvent extends Event {
    public let text: String;
}

public func MpOpenChatWith(text: String) -> Void {
    let evt = new MpOpenChatEvent();
    evt.text = text;
    GameInstance.GetUISystem(GetGameInstance()).QueueEvent(evt);
}
