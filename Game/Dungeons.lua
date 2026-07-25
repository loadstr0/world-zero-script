return function(ctx)
	local Dungeons = {}

	local Missions = ctx:Require("MissionsAPI")
	local Mobs = ctx:Require("MobsAPI")
	local Health = ctx:Require("Health")
	local Players = ctx.Services.Players
	local progressionSession = nil
	local progressionEnteredAt = setmetatable({}, { __mode = "k" })
	local progressionVisited = setmetatable({}, { __mode = "k" })

	local ROUTE_MARKERS = {
		TownTalkPart = true,
		CaveTrigger = true,
		BridgeTrigger = true,
		BoulderTrigger = true,
		BossIntroTrigger = true,
		FinalTeleport = true,
	}

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

	local function getRootPart()
		local player = Players.LocalPlayer
		local character = player and player.Character
		return character
			and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
			or nil
	end

	local function isInside(part, position)
		if not part or not position then
			return false
		end

		local localPosition = part.CFrame:PointToObjectSpace(position)
		local halfSize = part.Size * 0.5
		local margin = 4

		return math.abs(localPosition.X) <= halfSize.X + margin
			and math.abs(localPosition.Y) <= halfSize.Y + margin
			and math.abs(localPosition.Z) <= halfSize.Z + margin
	end

	local function isProgressionPart(part)
		if not part:IsA("BasePart") or not part.CanTouch then
			return false
		elseif ROUTE_MARKERS[part.Name] then
			return true
		end

		return part.Parent
			and part.Parent.Name == "Checkpoints"
			and string.match(part.Name, "^Checkpoint%d+$") ~= nil
	end

	local function resetProgression(session)
		if progressionSession == session then
			return
		end

		progressionSession = session
		progressionEnteredAt = setmetatable({}, { __mode = "k" })
		progressionVisited = setmetatable({}, { __mode = "k" })
	end

	local function getProgressionTarget(missionObjects, missionState)
		local root = getRootPart()

		if not missionObjects or not root then
			return nil, {}
		end

		resetProgression(tostring(game.PlaceId) .. ":" .. tostring(missionState.MissionID))

		local now = os.clock()
		local candidates = {}

		for _, instance in ipairs(missionObjects:GetDescendants()) do
			if isProgressionPart(instance) then
				local inside = isInside(instance, root.Position)

				if inside then
					progressionEnteredAt[instance] = progressionEnteredAt[instance] or now

					if now - progressionEnteredAt[instance] >= 0.75 then
						progressionVisited[instance] = now
					end
				else
					progressionEnteredAt[instance] = nil
				end

				table.insert(candidates, {
					Part = instance,
					Name = instance.Name,
					Position = instance.Position,
					Distance = (root.Position - instance.Position).Magnitude,
					VisitedAt = progressionVisited[instance],
					Inside = inside,
				})
			end
		end

		table.sort(candidates, function(a, b)
			if a.VisitedAt ~= nil and b.VisitedAt == nil then
				return false
			elseif a.VisitedAt == nil and b.VisitedAt ~= nil then
				return true
			elseif a.Distance ~= b.Distance then
				return a.Distance < b.Distance
			end

			return a.Name < b.Name
		end)

		local target = candidates[1]

		if target and target.VisitedAt then
			table.clear(progressionEnteredAt)
			table.clear(progressionVisited)

			for _, candidate in ipairs(candidates) do
				candidate.VisitedAt = nil
			end

			table.sort(candidates, function(a, b)
				if a.Distance ~= b.Distance then
					return a.Distance < b.Distance
				end

				return a.Name < b.Name
			end)
			target = candidates[1]
		end

		return target, candidates
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
		local progression, progressionTargets = getProgressionTarget(missionObjects, missionState)
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
		elseif not started and startTrigger then
			phase = "WaitingForStart"
		elseif progression and #protectedObjects == 0 then
			phase = "Progression"
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
			ProgressionTarget = progression and progression.Part or nil,
			ProgressionName = progression and progression.Name or nil,
			ProgressionPosition = progression and progression.Position or nil,
			ProgressionDistance = progression and progression.Distance or nil,
			ProgressionTargetCount = #progressionTargets,
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
			ProgressionName = state.ProgressionName,
			ProgressionTargetCount = state.ProgressionTargetCount,
			Error = state.Error,
		}
	end

	return Dungeons
end
