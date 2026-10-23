using CyberpunkSdk;
using CyberpunkSdk.Types;

namespace JobSystem.Board
{
    public struct Point2
    {
        public float X, Y, Z;
        public Point2(float x, float y, float z) { X = x; Y = y; Z = z; }

        public float DistanceTo(float x, float y)
        {
            var dx = X - x;
            var dy = Y - y;
            return MathF.Sqrt(dx * dx + dy * dy);
        }
    }

    /// <summary>One leg of an accepted contract, with its real position.</summary>
    public class Stage
    {
        public string Label = "";
        public StageGoal Goal;
        public Point2 Target;
        public float HoldSeconds;
        public string? SpawnVehicle;
        /// <summary>The player's game found solid ground near the target and moved it there.</summary>
        public bool Confirmed;
        public int Rerolls;
    }

    /// <summary>A job offered on the board, or one a player is working.</summary>
    public class Contract
    {
        public uint Id;
        public string JobId = "";
        public string Title = "";
        public string Detail = "";
        public uint Reward;
        public long Xp;
        public float TimeLimit;
        public List<Stage> Stages = new();
        public int LockedUntilLevel;

        /// <summary>Set for a call another player made (mechanic, Trauma Team, NCPD).</summary>
        public ulong CallerId;
        public uint CallerPays;
        public bool RepairsVehicle;
        public DateTime CreatedUtc = DateTime.UtcNow;

        public bool IsPlayerCall => CallerId != 0;
    }

    /// <summary>
    /// A job that runs on contracts (courier, tow, mechanic, Trauma Team, NCPD).
    /// The player picks a contract from the board; each stage puts a marker on
    /// their map, and the server checks they got there (and stayed, for work on
    /// foot) before moving on. Pay and XP come at the end.
    /// </summary>
    internal class ContractJob : Job
    {
        public JobDef Def { get; }
        public override CName Name { get; }

        public Contract? Active { get; private set; }
        private int _stage;
        private float _held;
        private float _elapsed;

        /// <summary>Offers shown to this player, made fresh when the board is opened.</summary>
        public List<Contract> Offers { get; } = new();
        public DateTime OffersMadeUtc = DateTime.MinValue;

        private const float ArriveRadius = 40f;
        private const float WorkRadius = 25f;
        private static readonly Logger logger = new("Contracts");

        public ContractJob(ulong id, JobDef def) : base(id)
        {
            Def = def;
            Name = new CName(def.Name);
        }

        public Stage? CurrentStage => Active != null && _stage < Active.Stages.Count ? Active.Stages[_stage] : null;

        public void Start(Contract contract)
        {
            Active = contract;
            _stage = 0;
            _held = 0;
            _elapsed = 0;
            Offers.Clear();

            var player = Server.PlayerSystem.GetById(Id);
            player?.SendChat("JOB", $"{contract.Title} accepted. Reward: {contract.Reward} eddies.");
            if (contract.TimeLimit > 0)
                player?.SendChat("JOB", $"Get it done within {contract.TimeLimit / 60f:0.#} minutes for full pay.");

            SendStage();
        }

        public void Cancel(string reason)
        {
            var contract = Active;
            if (contract == null)
                return;

            Active = null;
            Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ClearObjective(Id, reason);
            Server.PlayerSystem.GetById(Id)?.SendChat("JOB", reason);

            if (contract.IsPlayerCall)
            {
                // Put the call back up for someone else.
                Server.PlayerSystem.GetById(contract.CallerId)?.SendChat("JOB", $"Your responder dropped the call. It's back on the board.");
                JobBoard.Requeue(contract);
            }
        }

        public void SendStage()
        {
            var stage = CurrentStage;
            if (stage == null || Active == null)
                return;

            var step = Active.Stages.Count > 1 ? $" ({_stage + 1}/{Active.Stages.Count})" : "";
            var text = stage.Label + step;
            if (stage.Goal == StageGoal.WorkOnFoot)
                text += $" - stay on foot near the marker for {stage.HoldSeconds:0} s";
            else if (stage.Goal == StageGoal.ArriveInVehicle)
                text += " - arrive in a vehicle";

            Cyberpunk.Rpc.Client.Plugins.JobBoardClient.SetObjective(Id, stage.Target.X, stage.Target.Y, stage.Target.Z,
                text, stage.SpawnVehicle ?? "");
        }

        /// <summary>The player's game found the ground near the marker; use it if it's close to ours.</summary>
        public void ConfirmTarget(float x, float y, float z)
        {
            var stage = CurrentStage;
            if (stage == null || stage.Confirmed)
                return;
            if (stage.Target.DistanceTo(x, y) > 90f)
            {
                logger.Warn($"Player {Id} reported a target {stage.Target.DistanceTo(x, y):0} m from the real one; ignored.");
                return;
            }
            stage.Target = new Point2(x, y, z);
            stage.Confirmed = true;
        }

        /// <summary>The player's game found nowhere to stand near the marker (water, inside a building).</summary>
        public void Reroll()
        {
            var stage = CurrentStage;
            if (stage == null || stage.Confirmed)
                return;
            if (stage.Rerolls >= 6)
            {
                Cancel("Couldn't find a reachable spot for this contract. Pick another one.");
                return;
            }
            stage.Rerolls++;
            stage.Target = JobBoard.RandomPointNear(stage.Target, 150, 450, stage.Target.Z);
            SendStage();
        }

        public override void Update(float delta)
        {
        }

        public override void HeavyUpdate(float delta)
        {
            var contract = Active;
            var stage = CurrentStage;
            if (contract == null || stage == null)
                return;

            var player = Server.PlayerSystem.GetById(Id);
            if (player == null)
                return;

            _elapsed += delta;

            // A player call whose caller left is over.
            if (contract.IsPlayerCall && Server.PlayerSystem.GetById(contract.CallerId) == null)
            {
                Active = null;
                Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ClearObjective(Id, "The caller left the city. Call cancelled.");
                return;
            }

            var pos = player.MovementComponent.Position;
            var distance = stage.Target.DistanceTo(pos.X, pos.Y);
            var inVehicle = player.AttachmentComponent.Parent != 0;

            var done = false;
            switch (stage.Goal)
            {
                case StageGoal.Arrive:
                    done = distance < ArriveRadius;
                    break;
                case StageGoal.ArriveInVehicle:
                    done = distance < ArriveRadius && inVehicle;
                    break;
                case StageGoal.WorkOnFoot:
                    var near = distance < WorkRadius && !inVehicle;
                    // Work for a caller happens next to the caller.
                    if (near && contract.IsPlayerCall)
                    {
                        var caller = Server.PlayerSystem.GetById(contract.CallerId);
                        if (caller == null)
                            near = false;
                        else
                        {
                            var cpos = caller.MovementComponent.Position;
                            near = new Point2(pos.X, pos.Y, pos.Z).DistanceTo(cpos.X, cpos.Y) < WorkRadius;
                        }
                    }
                    if (near)
                    {
                        if (_held == 0)
                            player.SendChat("JOB", $"Working... stay here for {stage.HoldSeconds:0} seconds.");
                        _held += delta;
                        done = _held >= stage.HoldSeconds;
                    }
                    else if (_held > 0)
                    {
                        _held = 0;
                        player.SendChat("JOB", "You walked away; start again at the marker.");
                    }
                    break;
            }

            if (!done)
                return;

            _held = 0;
            _stage++;
            if (_stage < contract.Stages.Count)
            {
                SendStage();
                return;
            }

            Complete(contract);
        }

        private void Complete(Contract contract)
        {
            Active = null;
            var player = Server.PlayerSystem.GetById(Id);
            var economy = GameServices.Economy;

            uint pay = contract.Reward;
            if (contract.TimeLimit > 0 && _elapsed > contract.TimeLimit)
            {
                // Late: down to 40% of the reward, the later the less.
                var late = Math.Min(1f, (_elapsed - contract.TimeLimit) / contract.TimeLimit);
                pay = (uint)Math.Max(contract.Reward * 0.4f, contract.Reward * (1f - 0.6f * late));
            }

            bool paid;
            if (contract.IsPlayerCall && contract.CallerPays > 0)
            {
                paid = economy != null && economy.Transfer(contract.CallerId, Id, pay, $"{Def.Name}: service call");
                var caller = Server.PlayerSystem.GetById(contract.CallerId);
                caller?.SendChat("JOB", paid ? $"Job done. You paid {pay} eddies." : "Job done, but you couldn't cover the fee.");
                if (contract.RepairsVehicle)
                    Cyberpunk.Rpc.Client.Plugins.JobBoardClient.RepairMyVehicle(contract.CallerId, "Your car's been fixed up.");
            }
            else
            {
                paid = pay > 0 && economy != null && economy.Credit(Id, pay, $"{Def.Name}: {contract.Title}");
                if (contract.IsPlayerCall)
                    Server.PlayerSystem.GetById(contract.CallerId)?.SendChat("JOB", $"Your {Def.Name} responder has finished.");
            }

            if (paid)
                GameServices.Progression?.AddXp(Id, Def.Name, contract.Xp, $"{Def.Name}: {contract.Title}");

            var message = paid ? $"{contract.Title} complete. +{pay} eddies, +{contract.Xp} {Def.Name} XP."
                               : $"{contract.Title} complete, but the payment didn't go through.";
            player?.SendChat("JOB", message);
            Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ClearObjective(Id, message);
        }
    }
}
