using CyberpunkSdk;
using CyberpunkSdk.Types;
using JobSystem;
using JobSystem.Board;

namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class JobBoardServer
    {
        public static partial void OpenBoard_Impl(ulong playerId) => JobBoard.OpenBoard(playerId);

        public static partial void GoOnDuty_Impl(ulong playerId, string job) => JobBoard.GoOnDuty(playerId, job);

        public static partial void GoOffDuty_Impl(ulong playerId) => JobBoard.GoOffDuty(playerId);

        public static partial void OpenContracts_Impl(ulong playerId) => JobBoard.OpenContracts(playerId);

        public static partial void AcceptContract_Impl(ulong playerId, uint id) => JobBoard.AcceptContract(playerId, id);

        public static partial void CancelContract_Impl(ulong playerId) => JobBoard.CancelContract(playerId);

        public static partial void CallService_Impl(ulong playerId, string service) => JobBoard.CallService(playerId, service);

        public static partial void ConfirmTarget_Impl(ulong playerId, float x, float y, float z)
        {
            if (Plugin.Instance.JobManager.Get(playerId, out var job) && job is ContractJob contractJob)
                contractJob.ConfirmTarget(x, y, z);
        }

        public static partial void ReportUnreachable_Impl(ulong playerId)
        {
            if (Plugin.Instance.JobManager.Get(playerId, out var job) && job is ContractJob contractJob)
                contractJob.Reroll();
        }
    }
}

namespace JobSystem.Board
{
    /// <summary>
    /// The job board: what the player's game shows when they press the job key.
    /// Sends the list of jobs (with the player's level in each), the contracts
    /// on offer for the job they're on duty for, and handles calls players make
    /// for a mechanic, Trauma Team or NCPD.
    /// </summary>
    internal static class JobBoard
    {
        private static readonly Random Rng = new();
        private static readonly Logger logger = new("JobBoard");
        private static uint _nextId = 1;

        /// <summary>Open calls from players, by job id.</summary>
        private static readonly Dictionary<string, List<Contract>> Calls = new(StringComparer.OrdinalIgnoreCase);
        private static readonly Dictionary<(ulong, string), DateTime> LastCall = new();
        private static readonly object Lock = new();

        private const float CallLifetimeSeconds = 600;
        private const float CallCooldownSeconds = 120;
        private const float OfferLifetimeSeconds = 180;

        private static JobManager Jobs => Plugin.Instance.JobManager;

        // ---------------------------------------------------------------- board

        public static void OpenBoard(ulong playerId)
        {
            var parts = new List<string>();
            Jobs.Get(playerId, out var current);
            var onDuty = current switch
            {
                ContractJob c => c.Def.Id,
                Taxi => "taxi",
                _ => "",
            };

            var activeTitle = "";
            var activeStage = "";
            if (current is ContractJob cj && cj.Active != null)
            {
                activeTitle = cj.Active.Title;
                activeStage = cj.CurrentStage?.Label ?? "";
            }
            parts.Add(Record("H", onDuty, activeTitle, activeStage));

            foreach (var def in JobCatalog.Jobs)
            {
                var xp = GameServices.Progression?.GetXp(playerId, def.Name) ?? 0;
                var level = JobCatalog.LevelForXp(xp);
                var start = JobCatalog.XpForLevel(level);
                var next = level >= JobCatalog.MaxLevel ? xp : JobCatalog.XpForLevel(level + 1);
                int calls;
                lock (Lock) { calls = Calls.TryGetValue(def.Id, out var list) ? list.Count : 0; }

                parts.Add(Record("J", def.Id, def.Name, def.Category, def.Description, def.PayText,
                    level.ToString(), xp.ToString(), start.ToString(), next.ToString(),
                    onDuty == def.Id ? "1" : "0",
                    def.Service?.Id ?? "", def.Service?.Label ?? "", def.Service?.Description ?? "",
                    calls.ToString()));
            }

            Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ShowBoard(playerId, string.Join("^", parts));
        }

        public static void GoOnDuty(ulong playerId, string jobId)
        {
            var def = JobCatalog.Find(jobId);
            if (def == null)
                return;

            if (Jobs.Get(playerId, out var current))
            {
                var currentId = current is ContractJob c ? c.Def.Id : current is Taxi ? "taxi" : "";
                if (currentId == def.Id)
                {
                    OpenBoard(playerId);
                    return;
                }
                Jobs.Quit(playerId);
            }

            Jobs.SetJob(playerId, new CName(def.Name));
            Server.PlayerSystem.GetById(playerId)?.SendChat("JOB", $"You're on duty as {def.Name}.");
            OpenContracts(playerId);
        }

        public static void GoOffDuty(ulong playerId)
        {
            if (!Jobs.Get(playerId, out var job))
                return;
            Jobs.Quit(playerId);
            Server.PlayerSystem.GetById(playerId)?.SendChat("JOB", $"You're off duty.");
            OpenBoard(playerId);
        }

        // ---------------------------------------------------------------- contracts

        public static void OpenContracts(ulong playerId)
        {
            if (!Jobs.Get(playerId, out var job))
            {
                OpenBoard(playerId);
                return;
            }

            var player = Server.PlayerSystem.GetById(playerId);
            if (player == null)
                return;
            var pos = player.MovementComponent.Position;
            var here = new Point2(pos.X, pos.Y, pos.Z);
            var parts = new List<string>();

            if (job is Taxi)
            {
                parts.Add(Record("H", "taxi", "Taxi Driver"));
                foreach (var (id, data) in Cyberpunk.Rpc.Server.Plugins.TaxiServer.AvailableJobs)
                {
                    if (data.PlayerId == playerId)
                        continue;
                    var rider = Server.PlayerSystem.GetById(data.PlayerId);
                    var d = here.DistanceTo(data.PickUpLocation.X, data.PickUpLocation.Y);
                    parts.Add(Record("C", id.ToString(), "Ride request", $"{rider?.Username ?? "A player"} wants a ride.",
                        data.Reward.ToString(), ((int)d).ToString(), "1", "0"));
                }
                Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ShowContracts(playerId, string.Join("^", parts));
                return;
            }

            if (job is not ContractJob contractJob)
                return;

            var def = contractJob.Def;
            parts.Add(Record("H", def.Id, def.Name));

            var level = JobCatalog.LevelForXp(GameServices.Progression?.GetXp(playerId, def.Name) ?? 0);
            if (contractJob.Offers.Count == 0 || (DateTime.UtcNow - contractJob.OffersMadeUtc).TotalSeconds > OfferLifetimeSeconds)
            {
                contractJob.Offers.Clear();
                foreach (var tier in def.Tiers)
                {
                    if (tier.UnlockLevel > level)
                    {
                        contractJob.Offers.Add(new Contract
                        {
                            Id = NextId(), JobId = def.Id, Title = tier.Title, Detail = tier.Detail,
                            Reward = tier.BasePay, LockedUntilLevel = tier.UnlockLevel,
                        });
                        continue;
                    }
                    for (var i = 0; i < 2; i++)
                        contractJob.Offers.Add(MakeContract(def, tier, here, level));
                }
                contractJob.OffersMadeUtc = DateTime.UtcNow;
            }

            lock (Lock)
            {
                if (Calls.TryGetValue(def.Id, out var calls))
                {
                    foreach (var call in calls)
                    {
                        var target = call.Stages[0].Target;
                        parts.Add(Record("C", call.Id.ToString(), call.Title, call.Detail, call.Reward.ToString(),
                            ((int)here.DistanceTo(target.X, target.Y)).ToString(), "1", "0"));
                    }
                }
            }

            foreach (var offer in contractJob.Offers)
            {
                var distance = offer.Stages.Count > 0 ? (int)here.DistanceTo(offer.Stages[0].Target.X, offer.Stages[0].Target.Y) : 0;
                parts.Add(Record("C", offer.Id.ToString(), offer.Title, offer.Detail, offer.Reward.ToString(),
                    distance.ToString(), "0", offer.LockedUntilLevel.ToString()));
            }

            Cyberpunk.Rpc.Client.Plugins.JobBoardClient.ShowContracts(playerId, string.Join("^", parts));
        }

        public static void AcceptContract(ulong playerId, uint id)
        {
            if (!Jobs.Get(playerId, out var job))
                return;

            if (job is Taxi taxi)
            {
                taxi.AcceptJob(id);
                return;
            }

            if (job is not ContractJob contractJob)
                return;
            var player = Server.PlayerSystem.GetById(playerId);

            if (contractJob.Active != null)
            {
                player?.SendChat("JOB", "Finish or cancel your current contract first.");
                return;
            }

            Contract? contract = null;
            lock (Lock)
            {
                if (Calls.TryGetValue(contractJob.Def.Id, out var calls))
                {
                    contract = calls.FirstOrDefault(c => c.Id == id);
                    if (contract != null)
                    {
                        if (contract.CallerId == playerId)
                        {
                            player?.SendChat("JOB", "You can't answer your own call.");
                            return;
                        }
                        calls.Remove(contract);
                    }
                }
            }

            if (contract != null)
            {
                Server.PlayerSystem.GetById(contract.CallerId)?.SendChat("JOB",
                    $"{player?.Username ?? "A responder"} ({contractJob.Def.Name}) is on the way. Stay where you are.");
                contractJob.Start(contract);
                return;
            }

            contract = contractJob.Offers.FirstOrDefault(c => c.Id == id);
            if (contract == null)
            {
                player?.SendChat("JOB", "That contract's gone. Here's what's on offer now.");
                OpenContracts(playerId);
                return;
            }
            if (contract.LockedUntilLevel > 0)
            {
                player?.SendChat("JOB", $"That unlocks at {contractJob.Def.Name} level {contract.LockedUntilLevel}.");
                return;
            }

            contractJob.Start(contract);
        }

        public static void CancelContract(ulong playerId)
        {
            if (!Jobs.Get(playerId, out var job))
                return;
            if (job is ContractJob contractJob)
                contractJob.Cancel("Contract cancelled.");
            else if (job is Taxi taxi)
                taxi.CancelJob();
        }

        private static Contract MakeContract(JobDef def, ContractTier tier, Point2 start, int level)
        {
            var contract = new Contract
            {
                Id = NextId(),
                JobId = def.Id,
                Title = tier.Title,
                Detail = tier.Detail,
                Xp = tier.Xp,
                TimeLimit = tier.TimeLimit,
            };

            var from = start;
            float total = 0, typical = 0;
            foreach (var template in tier.Stages)
            {
                var point = RandomPointNear(from, template.MinDistance, template.MaxDistance, start.Z);
                total += from.DistanceTo(point.X, point.Y);
                typical += (template.MinDistance + template.MaxDistance) / 2f;

                string? vehicle = null;
                if (template.SpawnVehicle != null)
                {
                    var choices = tier.Vehicles is { Length: > 0 } ? tier.Vehicles : JobCatalog.EverydayCars;
                    vehicle = choices[Rng.Next(choices.Length)];
                }

                contract.Stages.Add(new Stage
                {
                    Label = template.Label,
                    Goal = template.Goal,
                    Target = point,
                    HoldSeconds = template.HoldSeconds,
                    SpawnVehicle = vehicle,
                });
                from = point;
            }

            // Longer than usual pays a bit more, shorter a bit less.
            var lengthFactor = typical > 0 ? Math.Clamp(total / typical, 0.8f, 1.3f) : 1f;
            var reward = tier.BasePay * JobCatalog.PayMultiplier(level) * lengthFactor;
            contract.Reward = (uint)(Math.Round(reward / 5.0) * 5);
            return contract;
        }

        public static Point2 RandomPointNear(Point2 from, float min, float max, float z)
        {
            var angle = Rng.NextDouble() * Math.PI * 2;
            var distance = min + (float)Rng.NextDouble() * (max - min);
            return new Point2(from.X + (float)Math.Cos(angle) * distance, from.Y + (float)Math.Sin(angle) * distance, z);
        }

        private static uint NextId()
        {
            lock (Lock) { return _nextId++; }
        }

        // ---------------------------------------------------------------- calls from players

        public static void CallService(ulong playerId, string serviceId)
        {
            var def = JobCatalog.Jobs.FirstOrDefault(j => j.Service != null && string.Equals(j.Service.Id, serviceId, StringComparison.OrdinalIgnoreCase));
            var player = Server.PlayerSystem.GetById(playerId);
            if (def?.Service == null || player == null)
                return;
            var service = def.Service;

            lock (Lock)
            {
                if (LastCall.TryGetValue((playerId, service.Id), out var last) && (DateTime.UtcNow - last).TotalSeconds < CallCooldownSeconds)
                {
                    player.SendChat("JOB", "You called recently. Give it a couple of minutes.");
                    return;
                }
                if (Calls.TryGetValue(def.Id, out var open) && open.Any(c => c.CallerId == playerId))
                {
                    player.SendChat("JOB", "Your call is still open. Hang tight.");
                    return;
                }
            }

            if (service.CallerPays > 0 && (GameServices.Economy?.GetBalance(playerId) ?? 0) < service.CallerPays)
            {
                player.SendChat("JOB", $"That costs {service.CallerPays} eddies and you can't cover it.");
                return;
            }

            var pos = player.MovementComponent.Position;
            var contract = new Contract
            {
                Id = NextId(),
                JobId = def.Id,
                Title = $"Call from {player.Username}",
                Detail = service.Description,
                Reward = service.CallerPays > 0 ? service.CallerPays : service.Reward,
                Xp = service.Xp,
                CallerId = playerId,
                CallerPays = service.CallerPays,
                RepairsVehicle = service.RepairsVehicle,
            };
            contract.Stages.Add(new Stage
            {
                Label = $"Reach {player.Username}",
                Goal = StageGoal.WorkOnFoot,
                Target = new Point2(pos.X, pos.Y, pos.Z),
                HoldSeconds = service.HoldSeconds,
                Confirmed = true,
            });

            lock (Lock)
            {
                if (!Calls.TryGetValue(def.Id, out var list))
                    Calls[def.Id] = list = new List<Contract>();
                list.Add(contract);
                LastCall[(playerId, service.Id)] = DateTime.UtcNow;
            }

            var responders = Server.PlayerSystem.PlayerIds
                .Where(id => id != playerId && Jobs.Get(id, out var j) && j is ContractJob cj && cj.Def.Id == def.Id)
                .ToList();
            foreach (var id in responders)
                Server.PlayerSystem.GetById(id)?.SendChat("JOB", $"New call from {player.Username}. Open the job board to take it.");

            player.SendChat("JOB", responders.Count > 0
                ? $"Call sent. {responders.Count} {def.Name} on duty. Stay where you are."
                : $"Call sent, but nobody's on duty as {def.Name} right now. It stays open for 10 minutes.");
        }

        /// <summary>A responder dropped a player's call: put it back for someone else.</summary>
        public static void Requeue(Contract contract)
        {
            if (Server.PlayerSystem.GetById(contract.CallerId) == null)
                return;
            contract.CreatedUtc = DateTime.UtcNow;
            lock (Lock)
            {
                if (!Calls.TryGetValue(contract.JobId, out var list))
                    Calls[contract.JobId] = list = new List<Contract>();
                list.Add(contract);
            }
        }

        /// <summary>Drops expired calls and calls from players who left.</summary>
        public static void Tick(float delta)
        {
            lock (Lock)
            {
                foreach (var list in Calls.Values)
                {
                    list.RemoveAll(c =>
                    {
                        var expired = (DateTime.UtcNow - c.CreatedUtc).TotalSeconds > CallLifetimeSeconds;
                        var gone = Server.PlayerSystem.GetById(c.CallerId) == null;
                        if (expired && !gone)
                            Server.PlayerSystem.GetById(c.CallerId)?.SendChat("JOB", "Nobody took your call. Try again later.");
                        return expired || gone;
                    });
                }
            }
        }

        // ---------------------------------------------------------------- helpers

        /// <summary>Fields joined with '~'; the separators can't appear inside a field.</summary>
        private static string Record(params string[] fields) =>
            string.Join("~", fields.Select(f => (f ?? "").Replace("~", "-").Replace("^", "-")));
    }
}
