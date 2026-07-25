return function(ctx)
	local Towers = {}

	local GameContext = ctx:Require("GameContext")
	local ReplicatedStorage = ctx.Services.ReplicatedStorage
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")

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

	local function getActiveArena(floor)
		local missionObjects = Workspace:FindFirstChild("MissionObjects")
		local arenas = missionObjects and missionObjects:FindFirstChild("Arena")

		if not arenas then
			return nil
		elseif floor % 5 == 0 then
			return arenas:FindFirstChild("BossArena")
		elseif floor % 2 == 0 then
			return arenas:FindFirstChild("2")
		end

		return arenas:FindFirstChild("1")
	end

	local function nearestPart(container)
		local root = GameContext.GetRootPart()
		local selected = nil
		local selectedDistance = math.huge

		for _, instance in ipairs(container and container:GetDescendants() or {}) do
			if instance:IsA("BasePart") and instance.CanTouch then
				local distance = root and (root.Position - instance.Position).Magnitude or 0

				if not selected or distance < selectedDistance then
					selected = instance
					selectedDistance = distance
				end
			end
		end

		return selected, selected and selectedDistance or nil
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
		local objective = tostring(value("ObjectiveMessage") or "")
		local lowerObjective = string.lower(objective)
		local arena = getActiveArena(floor)
		local spawn = getPart(arena and arena:FindFirstChild("Spawn"))
		local bossGate = Workspace:FindFirstChild("Boss_Gate")
		local interactions = bossGate and bossGate:FindFirstChild("Interactions")
		local entryPart, entryDistance = nearestPart(interactions)
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
			Objective = objective,
			Arena = arena,
			ArenaName = arena and arena.Name or nil,
			EntryTrigger = entryPart,
			EntryPosition = entryPart and entryPart.Position or nil,
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
