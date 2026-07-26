return function(ctx)
	local Watchdog = {}

	local HttpService = ctx.Services.HttpService
	local Players = ctx.Services.Players
	local Executor = ctx:Require("Executor")
	local Logger = ctx:Require("Logger")
	local activeTokens = setmetatable({}, { __mode = "k" })
	local statuses = setmetatable({}, { __mode = "k" })

	local SAMPLE_INTERVAL = 1
	local LOG_INTERVAL = 5
	local AUTOMATION_RESTART_DELAY = 4
	local TOWER_REPOSITION_DISTANCE = 1000
	local TOWER_REPOSITION_COOLDOWN = 10
	local LOG_FOLDER = "WorldZero"
	local LOG_FILE = LOG_FOLDER .. "/watchdog-latest.json"
	local DEATH_LOG_FILE = LOG_FOLDER .. "/death-latest.json"

	local function vectorTable(value)
		if typeof(value) ~= "Vector3" then
			return nil
		end

		return {
			X = math.floor(value.X * 100) / 100,
			Y = math.floor(value.Y * 100) / 100,
			Z = math.floor(value.Z * 100) / 100,
		}
	end

	local function getUiRoots()
		local player = Players.LocalPlayer
		local roots = {
			game:GetService("CoreGui"),
			player and player:FindFirstChildOfClass("PlayerGui"),
		}
		local huiOk, hui = pcall(function()
			return type(gethui) == "function" and gethui() or nil
		end)

		if huiOk and hui then
			table.insert(roots, hui)
		end

		return roots
	end

	local function findRayfields()
		local result = {}
		local seenRoots = {}
		local seenScreens = {}

		for _, root in ipairs(getUiRoots()) do
			if root and not seenRoots[root] then
				seenRoots[root] = true

				for _, descendant in ipairs(root:GetDescendants()) do
					if
						descendant:IsA("ScreenGui")
						and (
							descendant.Name == "Rayfield"
							or descendant.Name == "Rayfield-Old"
						)
						and not seenScreens[descendant]
					then
						seenScreens[descendant] = true
						table.insert(result, descendant)
					end
				end
			end
		end

		return result
	end

	local function keepSingleRayfield(runtime, status)
		local screens = findRayfields()
		local keep = runtime.UI
			and type(runtime.UI.GetRootGui) == "function"
			and runtime.UI:GetRootGui()
			or nil

		if not keep or not keep.Parent then
			for index = #screens, 1, -1 do
				if screens[index].Name == "Rayfield" then
					keep = screens[index]
					break
				end
			end
		end

		local removed = 0

		for _, screen in ipairs(screens) do
			if screen ~= keep then
				local destroyed = pcall(screen.Destroy, screen)

				if destroyed then
					removed = removed + 1
				end
			end
		end

		status.RayfieldCount = math.max(0, #screens - removed)
		status.DuplicateRayfieldsRemoved =
			(status.DuplicateRayfieldsRemoved or 0) + removed
	end

	local function getDungeonState(runtime)
		if not runtime.DungeonsAPI then
			return nil
		end

		local ok, state = pcall(runtime.DungeonsAPI.GetState)
		return ok and type(state) == "table" and state or nil
	end

	local function getHealth(runtime, character)
		if not runtime.Health then
			return nil
		end

		local ok, state = pcall(runtime.Health.GetState, character)
		return ok and type(state) == "table" and state or nil
	end

	local function repositionToTowerSpawn(runtime, status, dungeon, now)
		local tower = dungeon and dungeon.Tower
		local root = runtime.Game.GetRootPart()
		local spawnPosition = tower and tower.HoldPosition

		if
			not root
			or typeof(spawnPosition) ~= "Vector3"
			or dungeon.Phase == "Rewards"
			or dungeon.MissionOver
		then
			return
		end

		local distance = (root.Position - spawnPosition).Magnitude
		status.TowerSpawnDistance = math.floor(distance * 10) / 10

		if
			distance < TOWER_REPOSITION_DISTANCE
			or now - (status.LastTowerRepositionAt or 0)
				< TOWER_REPOSITION_COOLDOWN
		then
			return
		end

		local target = spawnPosition + Vector3.new(0, 8, 0)
		local rotation = root.CFrame.Rotation
		local moved = pcall(function()
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.CFrame = CFrame.new(target) * rotation
		end)

		if moved then
			status.LastTowerRepositionAt = now
			status.LastRecovery = "authoritative_tower_spawn"
			status.RecoveryCount = (status.RecoveryCount or 0) + 1
			Logger.warn(
				"Watchdog moved the character to the active tower arena spawn:",
				tower.ArenaName,
				"floor",
				tower.Floor
			)
		end
	end

	local function skipCutscene(runtime, status, now)
		if
			not runtime.State:Get("Dungeons.AutoSkipCutscenes", true)
			or now - (status.LastCutsceneAttemptAt or 0) < 0.5
			or not runtime.MissionsAPI
		then
			return
		end

		local activeOk, active = pcall(runtime.MissionsAPI.IsCutsceneActive)

		if not activeOk or active ~= true then
			return
		end

		status.LastCutsceneAttemptAt = now
		local skippedOk, skipped = pcall(runtime.MissionsAPI.SkipCutscene)

		if skippedOk and skipped == true then
			pcall(runtime.Actions.ResumeMovement)
			status.LastRecovery = "cutscene_skipped"
			status.RecoveryCount = (status.RecoveryCount or 0) + 1
		end
	end

	local function restartAutomation(runtime, status, now)
		if not runtime.FarmingEngine.IsEnabled(runtime) then
			status.AutomationMissingSince = nil
			return
		end

		local decision = runtime.FarmingEngine.GetStatus(runtime)

		if decision then
			status.AutomationMissingSince = nil
			return
		end

		status.AutomationMissingSince = status.AutomationMissingSince or now

		if
			now - status.AutomationMissingSince >= AUTOMATION_RESTART_DELAY
			and now - (status.LastAutomationRestartAt or 0)
				>= AUTOMATION_RESTART_DELAY
		then
			status.LastAutomationRestartAt = now
			pcall(runtime.FarmingEngine.Reconcile, runtime)
			status.LastRecovery = "automation_restarted"
			status.RecoveryCount = (status.RecoveryCount or 0) + 1
		end
	end

	local function buildSnapshot(runtime, status, dungeon)
		local player = Players.LocalPlayer
		local character = player and player.Character
		local root = runtime.Game.GetRootPart()
		local health = getHealth(runtime, character)
		local navigator = runtime.Navigator.GetState()
		local automation = runtime.FarmingEngine.GetStatus(runtime)
		local tower = dungeon and dungeon.Tower

		return {
			Timestamp = os.time(),
			PlaceId = game.PlaceId,
			JobId = game.JobId,
			Player = player and player.Name or nil,
			Position = root and vectorTable(root.Position) or nil,
			Health = health and health.Current or nil,
			MaxHealth = health and health.Maximum or nil,
			RayfieldCount = status.RayfieldCount,
			DuplicateRayfieldsRemoved = status.DuplicateRayfieldsRemoved or 0,
			RecoveryCount = status.RecoveryCount or 0,
			LastRecovery = status.LastRecovery,
			AutomationEnabled = runtime.FarmingEngine.IsEnabled(runtime),
			AutomationAlive = automation ~= nil,
			NavigatorStatus = navigator and navigator.Status or nil,
			NavigatorMode = navigator and navigator.Mode or nil,
			DungeonPhase = dungeon and dungeon.Phase or nil,
			MissionId = dungeon and dungeon.MissionID or nil,
			MobCount = dungeon and dungeon.MobCount or nil,
			TowerFloor = tower and tower.Floor or nil,
			TowerStartFloor = tower and tower.StartFloor or nil,
			TowerArena = tower and tower.ArenaName or nil,
			TowerArenaStreamed = tower and tower.Arena ~= nil or false,
			TowerSpawnDistance = status.TowerSpawnDistance,
			RouteError = automation and automation.RouteError or nil,
			Target = automation
				and automation.FarmTarget
				and automation.FarmTarget.ModelName
				or nil,
			TargetHealth = automation
				and automation.FarmTarget
				and automation.FarmTarget.Health
				and automation.FarmTarget.Health.Current
				or nil,
			Retreating = automation and automation.Retreating or false,
			LastDamage = runtime.FarmingEngine.GetRecentDamage
				and runtime.FarmingEngine.GetRecentDamage(runtime)
				or nil,
		}
	end

	local function writeSnapshot(snapshot, path)
		if not Executor.Has("WriteFile") then
			return false
		end

		if Executor.Has("MakeFolder") then
			pcall(Executor.MakeFolder, LOG_FOLDER)
		end

		local encodedOk, encoded = pcall(HttpService.JSONEncode, HttpService, snapshot)

		if not encodedOk then
			return false
		end

		return pcall(Executor.WriteFile, path or LOG_FILE, encoded)
	end

	local function writeDeathSnapshot(runtime, status, reason)
		local now = os.clock()

		if now - (tonumber(status.LastDeathSnapshotAt) or 0) < 2 then
			return
		end

		status.LastDeathSnapshotAt = now
		local snapshot = buildSnapshot(runtime, status, getDungeonState(runtime))
		snapshot.Event = reason
		writeSnapshot(snapshot, DEATH_LOG_FILE)
	end

	function Watchdog.Start(runtime)
		Watchdog.Stop(runtime)

		local token = {}
		local status = {
			StartedAt = os.clock(),
			RecoveryCount = 0,
			DuplicateRayfieldsRemoved = 0,
		}
		activeTokens[runtime] = token
		statuses[runtime] = status
		getgenv().WorldZeroWatchdogToken = token

		local player = Players.LocalPlayer

		if player then
			status.CharacterRemovingConnection = player.CharacterRemoving:Connect(function()
				writeDeathSnapshot(runtime, status, "CharacterRemoving")
			end)

			local function observeHumanoid(character)
				if status.HumanoidDiedConnection then
					status.HumanoidDiedConnection:Disconnect()
					status.HumanoidDiedConnection = nil
				end

				local humanoid = character and character:FindFirstChildOfClass("Humanoid")

				if humanoid then
					status.HumanoidDiedConnection = humanoid.Died:Connect(function()
						writeDeathSnapshot(runtime, status, "HumanoidDied")
					end)
				end
			end

			status.CharacterAddedConnection = player.CharacterAdded:Connect(observeHumanoid)
			observeHumanoid(player.Character)
		end

		task.spawn(function()
			local lastLogAt = 0

			while
				not runtime.Stopped
				and activeTokens[runtime] == token
				and getgenv().WorldZeroWatchdogToken == token
			do
				local now = os.clock()
				local dungeon = getDungeonState(runtime)

				keepSingleRayfield(runtime, status)
				skipCutscene(runtime, status, now)
				restartAutomation(runtime, status, now)

				if dungeon and dungeon.IsCelestialTower then
					repositionToTowerSpawn(runtime, status, dungeon, now)
				else
					status.TowerSpawnDistance = nil
				end

				status.LastSnapshot = buildSnapshot(runtime, status, dungeon)

				if now - lastLogAt >= LOG_INTERVAL then
					lastLogAt = now
					writeSnapshot(status.LastSnapshot)
				end

				task.wait(SAMPLE_INTERVAL)
			end
		end)

		return true
	end

	function Watchdog.Stop(runtime)
		local token = activeTokens[runtime]

		if token and getgenv().WorldZeroWatchdogToken == token then
			getgenv().WorldZeroWatchdogToken = nil
		end

		local status = statuses[runtime]

		for _, key in ipairs({
			"CharacterRemovingConnection",
			"CharacterAddedConnection",
			"HumanoidDiedConnection",
		}) do
			local connection = status and status[key]

			if connection then
				pcall(connection.Disconnect, connection)
				status[key] = nil
			end
		end

		activeTokens[runtime] = nil
	end

	function Watchdog.GetStatus(runtime)
		local status = statuses[runtime]

		if not status then
			return {
				Active = false,
			}
		end

		return {
			Active = activeTokens[runtime] ~= nil,
			RecoveryCount = status.RecoveryCount or 0,
			LastRecovery = status.LastRecovery,
			RayfieldCount = status.RayfieldCount,
			DuplicateRayfieldsRemoved = status.DuplicateRayfieldsRemoved or 0,
			TowerSpawnDistance = status.TowerSpawnDistance,
			LastSnapshot = status.LastSnapshot,
		}
	end

	return Watchdog
end
