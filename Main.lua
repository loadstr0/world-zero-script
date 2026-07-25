return function(ctx)
	local Main = {}
	local activeRuntime = nil

	local FEATURE_ORDER = {
		"Home",
		"Farming",
		"Gear",
		"Missions",
		"Loot",
		"Rewards",
		"Combat",
		"Teleports",
		"Player",
		"Settings",
	}

	local TELEPORT_RESUME_CONTROLS = {
		FarmingEnabled = "Farming.Enabled",
		QuestsEnabled = "Quests.Enabled",
		LootDropsEnabled = "Loot.DropsEnabled",
		LootChestsEnabled = "Loot.ChestsEnabled",
		GearEnabled = "Gear.Enabled",
	}

	local function restoreTeleportState(runtime, Logger)
		local env = getgenv()
		local encoded = env.WorldZeroTeleportResume

		if type(encoded) ~= "string" or encoded == "" then
			return false
		end

		local decodedOk, payload = pcall(ctx.Services.HttpService.JSONDecode, ctx.Services.HttpService, encoded)

		if not decodedOk or type(payload) ~= "table" or type(payload.State) ~= "table" then
			Logger.warn("Teleport resume payload was invalid:", payload)
			return false
		end

		env.WorldZeroTeleportResume = nil

		for key, value in pairs(payload.State) do
			local valueType = type(value)

			if type(key) == "string" and (valueType == "boolean" or valueType == "number" or valueType == "string") then
				runtime.State:Set(key, value)
			end
		end

		for controlName, stateKey in pairs(TELEPORT_RESUME_CONTROLS) do
			local control = runtime.Controls[controlName]
			local value = payload.State[stateKey]

			if control and type(control.Set) == "function" and type(value) == "boolean" then
				pcall(control.Set, control, value)
			end
		end

		pcall(runtime.FarmingEngine.Reconcile, runtime)
		pcall(runtime.GearEngine.Reconcile, runtime)
		pcall(runtime.InventoryEngine.Reconcile, runtime)

		runtime.TeleportResume = {
			QueuedAt = tonumber(payload.QueuedAt),
			Version = tonumber(payload.Version),
		}
		Logger.info("Restored automation state after teleport.")
		return true
	end

	local function formatRegistrationError(registerError)
		local message = tostring(registerError)

		if type(debug) == "table" and type(debug.traceback) == "function" then
			local ok, traceback = pcall(debug.traceback, message, 2)

			if ok and type(traceback) == "string" then
				return traceback
			end
		end

		return message
	end

	function Main.Start()
		if activeRuntime then
			Main.Stop()
		end

		local Logger = ctx:Require("Logger")
		print("")
		Logger.info("========== INITIALIZATION START ==========")

		local config = ctx:Require("Config").Resolve()
		local valid, reason = ctx:Require("Config").Validate(config)

		if not valid then
			error("Invalid configuration: " .. tostring(reason))
		end

		local janitor = ctx:Require("Janitor").new()
		local state = ctx:Require("State").new()
		local ui = ctx:Require("RayfieldUI").new(config)

		local runtime = {
			Context = ctx,
			Config = config,
			Logger = Logger,
			Executor = ctx:Require("Executor"),
			Updater = ctx:Require("Updater"),
			Janitor = janitor,
			State = state,
			Game = ctx:Require("GameContext"),
			Profile = ctx:Require("Profile"),
			Actions = ctx:Require("Actions"),
			CombatAPI = ctx:Require("CombatAPI"),
			Energy = ctx:Require("Energy"),
			Health = ctx:Require("Health"),
			Status = ctx:Require("Status"),
			Walkspeed = ctx:Require("Walkspeed"),
			MissionsAPI = ctx:Require("MissionsAPI"),
			QuestRoutesAPI = ctx:Require("QuestRoutesAPI"),
			QuestsAPI = ctx:Require("QuestsAPI"),
			TeleportAPI = ctx:Require("TeleportAPI"),
			MobsAPI = ctx:Require("MobsAPI"),
			TowersAPI = ctx:Require("TowersAPI"),
			DungeonRoutesAPI = ctx:Require("DungeonRoutesAPI"),
			DungeonsAPI = ctx:Require("DungeonsAPI"),
			DropsAPI = ctx:Require("DropsAPI"),
			ChestsAPI = ctx:Require("ChestsAPI"),
			InventoryAPI = ctx:Require("InventoryAPI"),
			GearAPI = ctx:Require("GearAPI"),
			PetsAPI = ctx:Require("PetsAPI"),
			StarterPassAPI = ctx:Require("StarterPassAPI"),
			Navigator = ctx:Require("Navigator"),
			FarmingEngine = ctx:Require("FarmingEngine"),
			GearEngine = ctx:Require("GearEngine"),
			InventoryEngine = ctx:Require("InventoryEngine"),
			Skills = ctx:Require("Skills"),
			Assassin = ctx:Require("Assassin"),
			Archer = ctx:Require("Archer"),
			Berserker = ctx:Require("Berserker"),
			Defender = ctx:Require("Defender"),
			Demon = ctx:Require("Demon"),
			Dragoon = ctx:Require("Dragoon"),
			DualWielder = ctx:Require("DualWielder"),
			Greatsword = ctx:Require("Greatsword"),
			Guardian = ctx:Require("Guardian"),
			Hunter = ctx:Require("Hunter"),
			IcefireMage = ctx:Require("IcefireMage"),
			Leviathan = ctx:Require("Leviathan"),
			Mage = ctx:Require("Mage"),
			MageOfLight = ctx:Require("MageOfLight"),
			MageOfShadows = ctx:Require("MageOfShadows"),
			Necromancer = ctx:Require("Necromancer"),
			Paladin = ctx:Require("Paladin"),
			Starbreaker = ctx:Require("Starbreaker"),
			Stormcaller = ctx:Require("Stormcaller"),
			Summoner = ctx:Require("Summoner"),
			Swordmaster = ctx:Require("Swordmaster"),
			Warlord = ctx:Require("Warlord"),
			ClassRegistry = ctx:Require("ClassRegistry"),
			Navigation = ctx:Require("Navigation"),
			UI = ui,
			Controls = {},
			Stopped = false,
		}

		function runtime.Stop()
			Main.Stop()
		end

		activeRuntime = runtime
		ctx.ActiveRuntime = runtime

		local identityConfig = config.Runtime or {}
		local identityWarningShown = false

		for _, moduleName in ipairs(FEATURE_ORDER) do
			local feature = ctx:Require(moduleName)

			if runtime.Executor.Has("SetThreadIdentity") then
				local identityOk, identityError = runtime.Executor.EnsureThreadIdentity(identityConfig.ThreadIdentity)

				if not identityOk and not identityWarningShown then
					identityWarningShown = true
					Logger.warn("Could not restore executor thread identity:", identityError)
				end
			end

			local ok, registerError = xpcall(function()
				feature.Register(runtime)
			end, formatRegistrationError)

			if not ok then
				Logger.error("Feature registration failed:", moduleName, registerError)
			end
		end

		runtime.ActiveClass = runtime.ClassRegistry.GetCurrentClass()
		local classConnection, classObserveError = runtime.ClassRegistry.Observe(function(className)
			if runtime.Stopped or className == runtime.ActiveClass or runtime.ClassReloadQueued then
				return
			end

			runtime.ClassReloadQueued = true
			Logger.info("Equipped class changed:", runtime.ActiveClass, "->", className)

			task.defer(function()
				task.wait(0.1)

				if not runtime.Stopped and activeRuntime == runtime then
					Main.Start()
				end
			end)
		end)

		if classConnection then
			janitor:Add(classConnection)
		elseif classObserveError then
			Logger.warn("Class change listener unavailable:", classObserveError)
		end

		ui:LoadConfiguration()
		local resumedAfterTeleport = restoreTeleportState(runtime, Logger)
		ui:Notify("World Zero", "Modular interface loaded.", 4, "circle-check")
		if resumedAfterTeleport then
			ui:Notify("Automation resumed", "Farming state was restored after teleport.", 5, 0)
		end
		Logger.info("Started in PlaceId", game.PlaceId)
		Logger.info("=========== INITIALIZATION END ===========")
		print("")

		return runtime
	end

	function Main.Stop()
		local runtime = activeRuntime

		if not runtime or runtime.Stopped then
			return
		end

		runtime.Stopped = true
		pcall(runtime.FarmingEngine.Stop, runtime)
		pcall(runtime.FarmingEngine.ClearSpeedBoost, runtime)
		pcall(runtime.GearEngine.Stop, runtime)
		pcall(runtime.InventoryEngine.Stop, runtime)

		if runtime.AutomationTargetProvider then
			pcall(runtime.Actions.ClearTargetProvider, runtime.AutomationTargetProvider)
		end

		runtime.Janitor:Cleanup()
		pcall(function()
			runtime.UI:Destroy()
		end)

		if ctx.ActiveRuntime == runtime then
			ctx.ActiveRuntime = nil
		end

		activeRuntime = nil
	end

	return Main
end
