using CyberpunkSdk;
using CyberpunkSdk.Systems;
using CyberpunkSdk.Types;


namespace Cyberpunk.Rpc.Server.Plugins
{
    public static partial class JobsServer
    {
        public static partial void SelectJob_Impl(ulong playerId, CName job)
        {
            JobSystem.Plugin.Instance.JobManager.SetJob(playerId, job);
        }

        public static partial void QuitJob_Impl(ulong playerId)
        {
            JobSystem.Plugin.Instance.JobManager.Quit(playerId);
        }
    }
}

namespace JobSystem
{
    internal class JobManager
    {
        private Dictionary<ulong, Job> playerJobs = new Dictionary<ulong, Job>();
        private Dictionary<CName, Func<ulong, Job>> availableJobs = new Dictionary<CName, Func<ulong, Job>>();

        // Players whose saved job is waiting to be given back, with seconds left.
        // The short wait lets their game finish loading before it gets the job UI.
        private Dictionary<ulong, float> pendingRestore = new Dictionary<ulong, float>();
        private const float RestoreDelaySeconds = 5.0f;

        private Logger logger = new Logger("Jobs");

        internal JobManager()
        {
            Server.PlayerSystem.PlayerJoinEvent += OnPlayerJoin;
            Server.PlayerSystem.PlayerLeftEvent += OnPlayerLeave;

            Server.World.UpdateEvent += Update;

            RegisterJob<DeliveryDriver>();
            RegisterJob<Police>();
            RegisterJob<Taxi>();

            Server.Timer.Add(Save, 300.0f);
            Server.Timer.Add(HeavyUpdate, 0.5f);
        }

        private void RegisterJob<T>() where T : Job
        {
            var jobCName = typeof(T).GetField("Job", System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static)?.GetValue(null) as CName;

            if(jobCName == null)
            {
                logger.Error("Attempt to register job without a name.");
                return;
            }

            availableJobs[jobCName] = (ulong id) => Activator.CreateInstance(typeof(T), [id]) as Job;

            logger.Info("\tRegistered job " + jobCName);
        }

        internal bool Get(ulong id, out Job? job)
        {
            return playerJobs.TryGetValue(id, out job);
        }

        public void SetJob(ulong id, CName name)
        {
            if(playerJobs.TryGetValue(id, out var jobName))
            {
                logger.Warn($"Player {id} tried to get new job {name} but already has a job {jobName}!");
                Cyberpunk.Rpc.Client.Plugins.JobsClient.SetActiveJob(id, jobName.Name);
                return;
            }

            if(availableJobs.TryGetValue(name, out var creator))
            {
                var job = creator(id);
                playerJobs.Add(id, job);
            }
            else
            {
                logger.Warn($"Player {id} tried to get new job {name} but it doesn't exist!");
                return;
            }

            logger.Info($"Player {id} got new job {name}.");

            // Remember the job so it comes back after a disconnect or restart.
            GameServices.Progression?.SetSavedJob(id, name.ToString());

            Cyberpunk.Rpc.Client.Plugins.JobsClient.SetActiveJob(id, name);
        }

        public void Quit(ulong id)
        {
            if(playerJobs.Remove(id, out var job))
            {
                logger.Info($"Player {id} quit job {job.Name}.");

                GameServices.Progression?.SetSavedJob(id, null);

                Cyberpunk.Rpc.Client.Plugins.JobsClient.SetActiveJob(id, new("None"));
            }
        }

        private void Update(float delta)
        {
            foreach (var job in playerJobs.Values)
            {
                job.Update(delta);
            }
        }

        private void HeavyUpdate(float delta)
        {
            RestoreSavedJobs(delta);

            foreach (var job in playerJobs.Values)
            {
                job.HeavyUpdate(delta);
            }
        }

        private void OnPlayerJoin(ulong id)
        {
            // The saved job is read a few seconds later (see RestoreSavedJobs), after
            // CharacterSystem has loaded the character and the game is ready.
            pendingRestore[id] = RestoreDelaySeconds;
        }

        private void RestoreSavedJobs(float delta)
        {
            if (pendingRestore.Count == 0)
                return;

            foreach (var id in pendingRestore.Keys.ToList())
            {
                var left = pendingRestore[id] - delta;
                if (left > 0)
                {
                    pendingRestore[id] = left;
                    continue;
                }

                pendingRestore.Remove(id);

                var saved = GameServices.Progression?.GetSavedJob(id);
                if (string.IsNullOrEmpty(saved) || playerJobs.ContainsKey(id))
                    continue;

                var name = new CName(saved);
                if (!availableJobs.ContainsKey(name))
                {
                    logger.Warn($"Player {id} had saved job '{saved}', which no longer exists.");
                    GameServices.Progression?.SetSavedJob(id, null);
                    continue;
                }

                logger.Info($"Restoring job {saved} for player {id}.");
                SetJob(id, name);
            }
        }

        private void OnPlayerLeave(ulong id)
        {
            pendingRestore.Remove(id);

            // Drop the in-memory job without clearing the saved one, so it's
            // given back next time they join.
            if (playerJobs.Remove(id, out var job))
            {
                // Put any half-done delivery or fare back on the board for others.
                try
                {
                    if (job is DeliveryDriver delivery)
                        delivery.CancelJob();
                    else if (job is Taxi taxi)
                        taxi.CancelJob();
                }
                catch (Exception ex)
                {
                    logger.Warn($"Cleaning up job for player {id} who left: {ex.Message}");
                }
            }
        }

        private void Save(float delta)
        {
            // Jobs are saved by CharacterSystem as they change; nothing to do here.
        }
    }
}
