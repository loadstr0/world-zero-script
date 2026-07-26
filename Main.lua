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

	local TELEPORT_STATE_VERSION = 2

	local function watchTeleportState(runtime)
		local refreshSerial = 0

		for stateKey in pairs(runtime.State.Values) do
			runtime.Janitor:Add(runtime.State:Subscribe(stateKey, function()
				refreshSerial = refreshSerial + 1
				local serial = refreshSerial

				task.delay(0.2, function()
					if
						serial == refreshSerial
						and not runtime.Stopped
						and ctx.ActiveRuntime == runtime
					then
						local queued, queueError = runtime.TeleportAPI.QueueBootstrap()

						if not queued then
							runtime.Logger.warn(
								"Could not refresh teleport state:",
								queueError
							)
						end
					end
				end)
			end))
		end
	end

	local function migrateTeleportState(payload)
		local version = tonumber(payload.Version) or 1
		local state = payload.State

		if version < 2 then
			-- Version 1 persisted the original recovery profile, which could force
			-- 70-95% downtime even after the timer-aware defaults were introduced.
			state["Farming.DebuffSafetyThreshold"] = 45
			state["Farming.DodgeHealthThreshold"] = 50
			state["Farming.RetreatHealthThreshold"] = 35
			state["Farming.RecoveryResumeThreshold"] = 60
			state["Farming.ConservativeRecovery"] = false
			state["Farming.BossTimerSurvival"] = true
			state["Farming.BossRetreatHealthThreshold"] = 25
			state["Farming.BossUrgentTimeThreshold"] = 45
			state["Farming.BossRecoveryResumeThreshold"] = 45
			payload.Version = TELEPORT_STATE_VERSION
		end

		return state
	end

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
		local restoredState = migrateTeleportState(payload)

		for key, value in pairs(restoredState) do
			local valueType = type(value)

			if type(key) == "string" and (valueType == "boolean" or valueType == "number" or valueType == "string") then
				runtime.State:Set(key, value)
			end
		end

		for controlName, stateKey in pairs(TELEPORT_RESUME_CONTROLS) do
			local control = runtime.Controls[controlName]
			local value = restoredState[stateKey]

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

	local function releaseBootSafety(runtime)
		local env = getgenv()
		local safety = env.WorldZeroBootSafety

		if type(safety) ~= "table" then
			return false
		end

		safety.Active = false
		local root = runtime.Game.GetRootPart()
		local automationEnabled = runtime.FarmingEngine.IsEnabled(runtime)
		local returnCFrame = safety.OriginalCFrame
		local returnMode = "original_position"
		local dungeonState = nil

		if automationEnabled and runtime.DungeonsAPI then
			local ok, state = pcall(runtime.DungeonsAPI.GetState)

			if ok and type(state) == "table" and state.Active then
				dungeonState = state
			end
		end

		if dungeonState then
			local returnPosition = nil

			if runtime.MobsAPI then
				local ok, _, descriptor = pcall(runtime.MobsAPI.SelectTarget, {
					Range = math.huge,
					IncludeOwned = false,
				})

				if ok and descriptor and typeof(descriptor.Position) == "Vector3" then
					returnPosition = descriptor.Position
					returnMode = "live_mob_target"
				end
			end

			if typeof(returnPosition) ~= "Vector3" then
				if
					dungeonState.IsCelestialTower
					and tonumber(safety.InitialTowerFloor)
						== tonumber(safety.CurrentTowerFloor)
				then
					local towerSpawn = dungeonState.HoldPosition
					local originalPosition = safety.OriginalCFrame
						and safety.OriginalCFrame.Position
						or nil

					if
						typeof(towerSpawn) == "Vector3"
						and (
							typeof(originalPosition) ~= "Vector3"
							or (originalPosition - towerSpawn).Magnitude > 350
						)
					then
						-- A freshly joined tower can expose floor 50 while the
						-- character is still in Studio_Spawn_Room or a stale
						-- streamed room. The active arena's replicated Spawn is
						-- stronger evidence than that temporary boot position.
						returnPosition = towerSpawn
						returnMode = "authoritative_tower_spawn"
					else
						returnPosition = nil
						returnMode = "original_tower_spawn"
					end
				elseif dungeonState.IsCelestialTower then
					returnPosition = dungeonState.HoldPosition
						or dungeonState.ProgressionPosition
						or dungeonState.StartPosition
				else
					returnPosition = dungeonState.ProgressionPosition
						or dungeonState.StartPosition
						or dungeonState.PriorityOrigin
						or dungeonState.HoldPosition
				end
			end

			if returnMode == "original_tower_spawn" then
				returnCFrame = safety.OriginalCFrame
			elseif typeof(returnPosition) == "Vector3" then
				local rotation = safety.OriginalCFrame and safety.OriginalCFrame.Rotation or CFrame.identity
				returnCFrame = CFrame.new(returnPosition + Vector3.new(0, 18, 0)) * rotation
				if returnMode ~= "live_mob_target" then
					returnMode = dungeonState.IsCelestialTower
							and "current_tower_entry"
						or "current_dungeon_stage"
				end
			elseif
				tonumber(safety.InitialTowerFloor)
				and tonumber(safety.CurrentTowerFloor)
				and tonumber(safety.InitialTowerFloor) ~= tonumber(safety.CurrentTowerFloor)
			then
				-- Never send the character back to the previous tower floor.
				returnCFrame = nil
				returnMode = "tower_floor_changed_no_stale_restore"
			end
		end

		if root and root.Parent then
			pcall(function()
				if safety.Character == root.Parent and returnCFrame then
					root.CFrame = returnCFrame
				end

				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				root.Anchored = automationEnabled and false or safety.OriginalAnchored == true
			end)
		end

		runtime.BootSafety = {
			Used = true,
			Height = tonumber(safety.Height) or 0,
			AutomationRelease = automationEnabled == true,
			ReturnMode = returnMode,
			InitialTowerFloor = tonumber(safety.InitialTowerFloor),
			CurrentTowerFloor = tonumber(safety.CurrentTowerFloor),
		}
		env.WorldZeroBootSafety = nil
		return true
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
			HazardsAPI = ctx:Require("HazardsAPI"),
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
			Watchdog = ctx:Require("RuntimeWatchdog"),
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
		local queuedBootstrap, queueError = runtime.TeleportAPI.QueueBootstrap()

		if not queuedBootstrap then
			Logger.warn("Persistent teleport bootstrap unavailable:", queueError)
		end

		watchTeleportState(runtime)
		releaseBootSafety(runtime)
		runtime.Watchdog.Start(runtime)
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
		pcall(runtime.Watchdog.Stop, runtime)

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
