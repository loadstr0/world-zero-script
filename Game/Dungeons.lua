return function(ctx)
	local Dungeons = {}

	local Missions = ctx:Require("MissionsAPI")
	local Mobs = ctx:Require("MobsAPI")
	local Health = ctx:Require("Health")
	local Players = ctx.Services.Players

	local function rewardScreenVisible()
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		local screen = playerGui and playerGui:FindFirstChild("MissionRewards")

		if not screen or (screen:IsA("ScreenGui") and not screen.Enabled) then
			return false
		end

		local content = screen:FindFirstChild("MissionRewards")
		return content == nil or not content:IsA("GuiObject") or content.Visible
	end

	local function getPart(instance)
		if not instance then
			return nil
		elseif instance:IsA("BasePart") then
			return instance
		elseif instance:IsA("Attachment") then
			return instance.Parent
		elseif instance:IsA("Model") then
			return instance.PrimaryPart
				or instance:FindFirstChild("Collider", true)
				or instance:FindFirstChildWhichIsA("BasePart", true)
		end

		return nil
	end

	local function getProtectedObjects(missionObjects)
		local result = {}

		for _, instance in ipairs(missionObjects and missionObjects:GetDescendants() or {}) do
			if instance:IsA("Model") and instance:FindFirstChild("IgnorePlayerHits") then
				local health = Health.GetState(instance)
				local part = getPart(instance)

				if health and part then
					table.insert(result, {
						Model = instance,
						Name = instance.Name,
						Part = part,
						Position = part.Position,
						Health = health,
						HealthRatio = tonumber(health.Ratio) or 1,
					})
				end
			end
		end

		table.sort(result, function(a, b)
			if a.HealthRatio ~= b.HealthRatio then
				return a.HealthRatio < b.HealthRatio
			end

			return a.Name < b.Name
		end)

		return result
	end

	function Dungeons.GetState()
		local missionState = Missions.GetRuntimeState()

		if not missionState.Active then
			return {
				Active = false,
				Error = missionState.Error,
				Phase = "NotInDungeon",
			}
		end

		local missionObjects = workspace:FindFirstChild("MissionObjects")
		local missionStart = missionObjects and missionObjects:FindFirstChild("MissionStart", true)
		local startTrigger = missionStart and missionStart:FindFirstChild("Collider", true)
		local protectedObjects = getProtectedObjects(missionObjects)
		local mobs = Mobs.GetAll() or {}
		local mobCount = 0

		for _ in pairs(mobs) do
			mobCount = mobCount + 1
		end

		local started = missionState.Started or mobCount > 0
		local phase = "WaitingForStart"

		if rewardScreenVisible() then
			phase = "Rewards"
		elseif missionState.MissionOver then
			phase = missionState.MissionSucceeded and "Completed" or "Failed"
		elseif mobCount > 0 then
			phase = "Combat"
		elseif started then
			phase = "BetweenWaves"
		elseif not startTrigger then
			phase = "WaitingForMechanic"
		end

		local defense = protectedObjects[1]
		local fallback = missionObjects and missionObjects:FindFirstChild("Spawn", true)
		local fallbackPart = getPart(fallback)

		return {
			Active = true,
			Phase = phase,
			Mission = missionState.Mission,
			MissionID = missionState.MissionID,
			Started = started,
			MissionOver = missionState.MissionOver,
			MissionSucceeded = missionState.MissionSucceeded,
			Lives = missionState.Lives,
			RemainingTime = missionState.RemainingTime,
			Difficulty = missionState.Difficulty,
			MissionObjects = missionObjects,
			StartTrigger = startTrigger,
			StartPosition = getPart(startTrigger) and getPart(startTrigger).Position or nil,
			MobCount = mobCount,
			ProtectedObjects = protectedObjects,
			PriorityDefense = defense,
			PriorityOrigin = defense and defense.Position or nil,
			HoldPosition = defense and defense.Position or (fallbackPart and fallbackPart.Position or nil),
		}
	end

	function Dungeons.Describe()
		local state = Dungeons.GetState()

		return {
			Active = state.Active,
			Phase = state.Phase,
			MissionID = state.MissionID,
			Started = state.Started,
			MobCount = state.MobCount,
			ProtectedObjectCount = type(state.ProtectedObjects) == "table" and #state.ProtectedObjects or 0,
			HasStartTrigger = state.StartPosition ~= nil,
			Error = state.Error,
		}
	end

	return Dungeons
end
