using CyberpunkSdk.Game;
using CyberpunkSdk.Internal;

namespace Server.Loader.Game
{
    public class PlayerSystem : CyberpunkSdk.Game.PlayerSystem
    {
        public override IEnumerable<ulong> PlayerIds => _players;

        private readonly List<ulong> _players = [];

        internal PlayerSystem()
        {
        }

        internal void PlayerJoin(ulong Id)
        {
            OnPlayerJoin(Id);
            _players.Add(Id);
        }

        internal void PlayerLeft(ulong Id)
        {
            _players.Remove(Id);
            OnPlayerLeft(Id);
        }

        public override Player? GetById(ulong Id)
        {
            // A player who has left has no native object; report that as null
            // instead of a wrapper that throws on first use.
            var native = IPlayerManager.Get().GetPlayer(Id);
            return native == null ? null : new Player(native);
        }
    }
}
