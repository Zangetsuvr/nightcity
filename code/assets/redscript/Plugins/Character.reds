module CyberpunkMP.Plugins

import CyberpunkMP.*
import CyberpunkMP.World.*

// Money and progress are owned by the server (CharacterSystem plugin).
// The game never decides how many eddies a player has: it only shows what the
// server sends. Anything the game adds or removes on its own is undone at the
// next sync, and big jumps are reported to the server as possible cheating.

public native class CharacterServer extends ServerRpc {
    // Ask the server to send balance and progress again.
    public static native func RequestSync() -> Void;

    // Tell the server our eddies changed without its say-so (cheat detection).
    public static native func ReportLocalBalance(localBalance: Int64, lastFromServer: Int64) -> Void;
}

// Holds what the server last told us. Client RPC functions don't run on a
// lasting object, so state lives in this game system instead.
public class CharacterState extends ScriptableSystem {
    public let lastBalance: Int64;
    public let hasBalance: Bool;
    public let level: Int32;
    public let xp: Int64;
    public let nextLevelXp: Int64;

    public static func Get(game: GameInstance) -> ref<CharacterState> {
        return GameInstance.GetScriptableSystemsContainer(game).Get(n"CyberpunkMP.Plugins.CharacterState") as CharacterState;
    }
}

public class CharacterClient extends ClientRpc {
    // Make the eddies in the player's inventory match the server's balance.
    public func SetBalance(balance: Int64) -> Void {
        let game = GetGameInstance();
        let player = GetPlayer(game);
        let state = CharacterState.Get(game);
        if !IsDefined(player) || !IsDefined(state) {
            return;
        }

        let ts = GameInstance.GetTransactionSystem(game);
        let current = Cast<Int64>(ts.GetItemQuantity(player, MarketSystem.Money()));

        // If our eddies moved since the server's last update, something other
        // than the server changed them (a cheat, a console command, a vendor).
        // Report it; the server decides whether it's worth flagging.
        if state.hasBalance && current != state.lastBalance {
            CharacterServer.ReportLocalBalance(current, state.lastBalance);
        }
        state.lastBalance = balance;
        state.hasBalance = true;

        let diff = balance - current;
        if diff > 0l {
            ts.GiveItem(player, MarketSystem.Money(), Cast<Int32>(diff));
        } else {
            if diff < 0l {
                ts.RemoveItem(player, MarketSystem.Money(), Cast<Int32>(-diff));
            }
        }
    }

    // Move the player (the server does this once for a brand-new character,
    // out of the clean start's holding room to the server's start point).
    public func Teleport(x: Float, y: Float, z: Float, yaw: Float) -> Void {
        let game = GetGameInstance();
        let player = GetPlayer(game);
        if !IsDefined(player) {
            return;
        }
        GameInstance.GetTeleportationFacility(game).Teleport(player, new Vector4(x, y, z, 1.0), new EulerAngles(0.0, 0.0, yaw));
    }

    // Street Cred level and XP from the server, kept for UI to read later.
    public func SetProgress(level: Int32, xp: Int64, nextLevelXp: Int64) -> Void {
        let state = CharacterState.Get(GetGameInstance());
        if !IsDefined(state) {
            return;
        }
        state.level = level;
        state.xp = xp;
        state.nextLevelXp = nextLevelXp;
    }
}
