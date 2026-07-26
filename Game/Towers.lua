return function(ctx)
	local Towers = {}

	local GameContext = ctx:Require("GameContext")
	local ReplicatedStorage = ctx.Services.ReplicatedStorage
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local Players = ctx.Services.Players or game:GetService("Players")
	local streamRequests = {}
	local arenaStreamHints = {
		["1"] = Vector3.new(405.7, 13.05, 716.55),
		["2"] = Vector3.new(-11106.3, 13.05, 6729),
	}

	local function getPart(instance)
		if not instance then
			return nil
		elseif instance:IsA("BasePart") then
			return instance
		elseif instance:IsA("Attachment") then
			return instance.Parent
		elseif instance:IsA("Model") then
			return instance.PrimaryPart
				or instance:FindFirstChild("Interaction", true)
				or instance:FindFirstChildWhichIsA("BasePart", true)
		end

		return nil
	end

	local function value(name)
		local instance = ReplicatedStorage:FindFirstChild(name)
		return instance and instance:IsA("ValueBase") and instance.Value or nil
	end

	local function isArenaEntryFloor(floor, startFloor)
		local relativeFloor = math.max(0, floor - startFloor)
		-- A checkpoint run may begin on a multiple of five (for example 50),
		-- but that first room is still a normal wave. The live mission
		-- controller only enables the boss/miniboss gate after at least four
		-- floors have elapsed and the current floor is a multiple of five.
		return relativeFloor >= 4 and floor % 5 == 0
	end

	local function getActiveArena(floor, startFloor)
		local missionObjects = Workspace:FindFirstChild("MissionObjects")
		local arenas = missionObjects and missionObjects:FindFirstChild("Arena")

		if not arenas then
			return nil, nil
		elseif isArenaEntryFloor(floor, startFloor) then
			return arenas:FindFirstChild("BossArena"), "BossArena"
		elseif floor % 2 == 0 then
			return arenas:FindFirstChild("2"), "2"
		end

		return arenas:FindFirstChild("1"), "1"
	end

	local function requestArenaStream(arenaName, spawn)
		if spawn then
			arenaStreamHints[arenaName] = spawn.Position
			streamRequests[arenaName] = nil
			return
		end

		local hint = arenaStreamHints[arenaName]
		local player = Players.LocalPlayer
		local now = os.clock()

		if
			typeof(hint) ~= "Vector3"
			or not player
			or type(player.RequestStreamAroundAsync) ~= "function"
			or now - (tonumber(streamRequests[arenaName]) or -math.huge) < 5
		then
			return
		end

		streamRequests[arenaName] = now
		task.spawn(function()
			pcall(player.RequestStreamAroundAsync, player, hint, 5)
		end)
	end

	local function getArenaEntry(bossGate)
		local root = GameContext.GetRootPart()
		local interactions = bossGate and bossGate:FindFirstChild("Interactions")
		local selected = nil
		local selectedPosition = nil
		local selectedDistance = math.huge

		for _, part in ipairs(interactions and interactions:GetChildren() or {}) do
			if part:IsA("BasePart") and part.CanTouch then
				local position = part.Position

				if root then
					local closestOk, closest = pcall(
						part.GetClosestPointOnSurface,
						part,
						root.Position
					)

					if closestOk and typeof(closest) == "Vector3" then
						position = closest
					end
				end

				local distance = root
						and (root.Position - position).Magnitude
					or 0

				if not selected or distance < selectedDistance then
					selected = part
					selectedPosition = position
					selectedDistance = distance
				end
			end
		end

		return selected, selectedPosition, selected and selectedDistance or nil
	end

	local function portalReady(arena, interaction)
		local location = getPart(arena and arena:FindFirstChild("TeleporterLocation"))

		if not location or not interaction then
			return false
		end

		return (location.Position - interaction.Position).Magnitude <= 60
	end

	function Towers.GetState(missionState, mobCount)
		local mission = missionState and missionState.Mission

		if not mission or mission.IsCelestialTower ~= true then
			return {
				Active = false,
				Supported = false,
			}
		end

		local floor = tonumber(value("ReplicateTowerFloor")) or 1
		local startFloor = tonumber(value("ReplicateTowerStartFloor")) or floor
		local requiresArenaEntry = isArenaEntryFloor(floor, startFloor)
		local objective = tostring(value("ObjectiveMessage") or "")
		local lowerObjective = string.lower(objective)
		local arena, arenaName = getActiveArena(floor, startFloor)
		local spawn = getPart(arena and arena:FindFirstChild("Spawn"))
		requestArenaStream(arenaName, spawn)
		local bossGate = Workspace:FindFirstChild("Boss_Gate")
		local entryPart, entryPosition, entryDistance = nil, nil, nil

		if requiresArenaEntry then
			entryPart, entryPosition, entryDistance = getArenaEntry(bossGate)
		end
		local lobbyTeleport = Workspace:FindFirstChild("LobbyTeleport")
		local portal = getPart(lobbyTeleport and lobbyTeleport:FindFirstChild("Interaction"))
		local isPortalReady = portalReady(arena, portal)
		local phase = "TowerWaiting"

		if (tonumber(mobCount) or 0) > 0 then
			phase = "Combat"
		elseif string.find(lowerObjective, "enter the arena", 1, true) then
			phase = "TowerEnter"
		elseif
			string.find(lowerObjective, "advance to the next floor", 1, true)
			or isPortalReady
		then
			phase = "TowerAdvance"
		end

		return {
			Active = true,
			Supported = true,
			IsCelestialTower = true,
			Phase = phase,
			Floor = floor,
			StartFloor = startFloor,
			RequiresArenaEntry = requiresArenaEntry,
			Objective = objective,
			Arena = arena,
			ArenaName = arenaName,
			EntryTrigger = entryPart,
			EntryPosition = entryPosition,
			EntryDistance = entryDistance,
			Portal = portal,
			PortalPosition = portal and portal.Position or nil,
			PortalReady = isPortalReady,
			HoldPosition = spawn and spawn.Position or nil,
		}
	end

	function Towers.Describe(missionState, mobCount)
		local state = Towers.GetState(missionState, mobCount)

		return {
			Active = state.Active,
			Supported = state.Supported,
			IsCelestialTower = state.IsCelestialTower,
			Phase = state.Phase,
			Floor = state.Floor,
			ArenaName = state.ArenaName,
			Objective = state.Objective,
			HasEntryTrigger = state.EntryPosition ~= nil,
			PortalReady = state.PortalReady,
		}
	end

	return Towers
end
