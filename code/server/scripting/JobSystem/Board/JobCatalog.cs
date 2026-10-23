namespace JobSystem.Board
{
    /// <summary>What a player has to do at one point of a contract.</summary>
    public enum StageGoal
    {
        /// <summary>Get within range, any way you like.</summary>
        Arrive,
        /// <summary>Get within range while driving or riding a vehicle.</summary>
        ArriveInVehicle,
        /// <summary>Stay within range, on foot, for HoldSeconds (repairs, treating a patient).</summary>
        WorkOnFoot,
    }

    /// <summary>One leg of a contract, generated relative to where the last one ended.</summary>
    public record StageTemplate(
        string Label,
        StageGoal Goal,
        float MinDistance,
        float MaxDistance,
        float HoldSeconds = 0,
        /// <summary>A vehicle record the player's game puts at this point (tow jobs).</summary>
        string? SpawnVehicle = null);

    /// <summary>A kind of contract a job offers, unlocked at a job level.</summary>
    public record ContractTier(
        string Title,
        string Detail,
        int UnlockLevel,
        uint BasePay,
        long Xp,
        StageTemplate[] Stages,
        /// <summary>Seconds to finish once accepted; 0 = no limit. Pay drops as time runs out.</summary>
        float TimeLimit = 0,
        /// <summary>Picked from at random when this tier spawns a vehicle.</summary>
        string[]? Vehicles = null);

    /// <summary>A service other players can call from the job board (mechanic, Trauma Team, NCPD).</summary>
    public record ServiceCall(
        string Id,
        string Label,
        string Description,
        /// <summary>What the caller pays the responder. 0 = the city pays Reward instead.</summary>
        uint CallerPays,
        uint Reward,
        long Xp,
        float HoldSeconds,
        /// <summary>Repair the caller's car when the job is done.</summary>
        bool RepairsVehicle);

    public record JobDef(
        string Id,
        string Name,
        string Category,
        string Description,
        string PayText,
        ContractTier[] Tiers,
        ServiceCall? Service = null);

    /// <summary>
    /// Every job on the job board. Taxi Driver is listed here for the board but
    /// runs its own flow (Taxi.cs): its contracts are other players' ride requests.
    /// </summary>
    public static class JobCatalog
    {
        public const int MaxLevel = 20;

        public static readonly string[] EverydayCars =
        {
            "Vehicle.v_standard2_archer_hella_player",
            "Vehicle.v_standard2_makigai_maimai_player",
            "Vehicle.v_standard2_villefort_cortes_player",
            "Vehicle.v_standard25_thorton_colby_player",
            "Vehicle.v_standard3_thorton_mackinaw_player",
        };

        public static readonly string[] RepoCars =
        {
            "Vehicle.v_sport2_mizutani_shion_player",
            "Vehicle.v_sport1_herrera_outlaw_player",
            "Vehicle.v_sport2_quadra_type66_player",
            "Vehicle.v_sport1_rayfield_caliburn_player",
        };

        public static readonly JobDef[] Jobs =
        {
            new("courier", "Courier", "Logistics",
                "Pick packages up and drop them off across Night City. Short hops to start with; longer runs unlock as you level up and pay a lot more.",
                "120 - 900 eddies a run",
                new[]
                {
                    new ContractTier("Local drop", "Short run in the neighbourhood.", 1, 120, 25, new[]
                    {
                        new StageTemplate("Pick up the package", StageGoal.WorkOnFoot, 150, 450, 3),
                        new StageTemplate("Deliver the package", StageGoal.WorkOnFoot, 400, 900, 3),
                    }),
                    new ContractTier("Cross-town", "Across a district or two.", 3, 320, 60, new[]
                    {
                        new StageTemplate("Pick up the package", StageGoal.WorkOnFoot, 200, 600, 3),
                        new StageTemplate("Deliver the package", StageGoal.WorkOnFoot, 900, 1800, 3),
                    }),
                    new ContractTier("Long haul", "Freight run to the other side of the city. Needs wheels.", 6, 900, 150, new[]
                    {
                        new StageTemplate("Load the freight", StageGoal.WorkOnFoot, 200, 700, 5),
                        new StageTemplate("Drive the freight to the drop", StageGoal.ArriveInVehicle, 1800, 3500),
                    }),
                }),

            new("tow", "Tow Truck", "Logistics",
                "Recover abandoned cars and bring them to the impound lot. Higher levels get repo orders on expensive cars, which pay more.",
                "400 - 950 eddies a car",
                new[]
                {
                    new ContractTier("Abandoned car", "Recover a car left on the street.", 1, 400, 70, new[]
                    {
                        new StageTemplate("Find the abandoned car", StageGoal.Arrive, 300, 1200, 0, "car"),
                        new StageTemplate("Drive it to the impound lot", StageGoal.ArriveInVehicle, 800, 2000),
                    }, 0, EverydayCars),
                    new ContractTier("Repo order", "Repossess a car whose owner stopped paying.", 4, 950, 160, new[]
                    {
                        new StageTemplate("Find the car on the repo order", StageGoal.Arrive, 500, 1600, 0, "car"),
                        new StageTemplate("Drive it to the impound lot", StageGoal.ArriveInVehicle, 1000, 2500),
                    }, 0, RepoCars),
                }),

            new("mechanic", "Mechanic", "Services",
                "Answer breakdown calls around the city and get people moving again. Players who call a mechanic from the job board show up here first.",
                "250 - 600 eddies a call",
                new[]
                {
                    new ContractTier("Breakdown call", "A car's stuck at the side of the road.", 1, 250, 45, new[]
                    {
                        new StageTemplate("Repair the broken-down car", StageGoal.WorkOnFoot, 300, 1200, 10),
                    }),
                    new ContractTier("Roadside rescue", "Bigger job: a convoy with two broken cars.", 4, 600, 110, new[]
                    {
                        new StageTemplate("Repair the first car", StageGoal.WorkOnFoot, 400, 1400, 10),
                        new StageTemplate("Repair the second car", StageGoal.WorkOnFoot, 150, 500, 10),
                    }),
                },
                new ServiceCall("mechanic", "Call a mechanic",
                    "A mechanic on duty comes to you and repairs your car. Costs 300 eddies, paid when it's done.",
                    300, 0, 70, 10, true)),

            new("trauma", "Trauma Team", "Emergency",
                "Respond to medical emergencies. Get there fast: pay drops the longer it takes. Players who call Trauma Team from the job board show up here first.",
                "500 eddies a call, less if you're slow",
                new[]
                {
                    new ContractTier("Emergency call", "Someone's down and needs help now.", 1, 500, 80, new[]
                    {
                        new StageTemplate("Treat the patient", StageGoal.WorkOnFoot, 400, 1500, 15),
                    }, 240),
                },
                new ServiceCall("trauma", "Call Trauma Team",
                    "A Trauma Team medic on duty comes to your position. Free for you; the city pays them.",
                    0, 400, 80, 15, false)),

            new("ncpd", "NCPD", "Emergency",
                "Respond to incidents across the city and secure the scene. Get there fast: pay drops the longer it takes. Players who call NCPD from the job board show up here first.",
                "450 eddies a call, less if you're slow",
                new[]
                {
                    new ContractTier("Incident report", "Reported disturbance. Get there and secure the area.", 1, 450, 75, new[]
                    {
                        new StageTemplate("Secure the scene", StageGoal.WorkOnFoot, 400, 1500, 15),
                    }, 240),
                },
                new ServiceCall("ncpd", "Call NCPD",
                    "An officer on duty comes to your position. Free for you; the city pays them.",
                    0, 350, 70, 15, false)),

            new("taxi", "Taxi Driver", "Services",
                "Pick up players who request a ride and drive them to where they're going. The rider pays the fare.",
                "100 eddies a ride",
                Array.Empty<ContractTier>()),
        };

        public static JobDef? Find(string id) =>
            Jobs.FirstOrDefault(j => string.Equals(j.Id, id, StringComparison.OrdinalIgnoreCase)
                                     || string.Equals(j.Name, id, StringComparison.OrdinalIgnoreCase));

        /// <summary>Jobs saved under older names come back as their replacement.</summary>
        public static JobDef? FindSaved(string saved) => saved switch
        {
            "Delivery Driver" => Find("courier"),
            "Police" => Find("ncpd"),
            _ => Find(saved),
        };

        // Same curve as Street Cred: level L takes 50 * L * (L - 1) XP in total.
        public static long XpForLevel(int level) => level <= 1 ? 0 : 50L * level * (level - 1);

        public static int LevelForXp(long xp)
        {
            var level = 1;
            while (level < MaxLevel && xp >= XpForLevel(level + 1))
                level++;
            return level;
        }

        /// <summary>+4% pay per level above 1, up to +50%.</summary>
        public static double PayMultiplier(int level) => 1.0 + Math.Min(0.5, 0.04 * (level - 1));
    }
}
