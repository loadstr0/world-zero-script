return function(ctx)
	local DungeonObjectives = {}

	local ReplicatedStorage = ctx.Services.ReplicatedStorage
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local GameContext = ctx:Require("GameContext")
	local lastActivations = setmetatable({}, { __mode = "k" })

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

	local function objectiveMessage()
		local value = ReplicatedStorage:FindFirstChild("ObjectiveMessage")

		if value and value:IsA("ValueBase") then
			return tostring(value.Value or "")
		end

		return ""
	end

	local function target(instance, kind, label)
		local part = getPart(instance)
		local root = GameContext.GetRootPart()

		if not part then
			return nil
		end

		return {
			Instance = instance,
			Part = part,
			Kind = kind,
			Name = label or instance.Name,
			Position = part.Position,
			Distance = root and (root.Position - part.Position).Magnitude or nil,
		}
	end

	local function nearest(targets)
		table.sort(targets, function(a, b)
			local aDistance = tonumber(a.Distance) or math.huge
			local bDistance = tonumber(b.Distance) or math.huge

			if aDistance ~= bDistance then
				return aDistance < bDistance
			end

			return tostring(a.Name) < tostring(b.Name)
		end)

		return targets[1]
	end

	local function collectWorkspaceMarkers(namePattern, kind)
		local result = {}

		for _, child in ipairs(Workspace:GetChildren()) do
			if string.match(child.Name, namePattern) then
				local entry = target(child, kind)

				if entry then
					table.insert(result, entry)
				end
			end
		end

		return result
	end

	local function missionFourObjective(lowerObjective, missionObjects)
		if string.find(lowerObjective, "rescue the villagers", 1, true) then
			local targets = collectWorkspaceMarkers("^Cage%d+Marker$", "RescueVillager")

			return nearest(targets), #targets, "RescueVillagers"
		elseif string.find(lowerObjective, "walk the plank", 1, true) then
			local cannonTrigger = missionObjects
				and missionObjects:FindFirstChild("CannonTrigger", true)

			return target(cannonTrigger, "ObjectiveTrigger", "CannonTrigger"), 1, "WalkThePlank"
		end

		return nil, 0, nil
	end

	local function genericObjective(lowerObjective)
		if lowerObjective == "" then
			return nil, 0, nil
		end

		local targets = collectWorkspaceMarkers("^.+Marker$", "ObjectiveMarker")

		return nearest(targets), #targets, targets[1] and "WorkspaceMarker" or nil
	end

	function DungeonObjectives.GetState(missionState, missionObjects)
		local message = objectiveMessage()
		local lowerObjective = string.lower(message)
		local missionID = tonumber(missionState and missionState.MissionID)
		local selected, count, mechanic

		if missionID == 4 then
			selected, count, mechanic = missionFourObjective(lowerObjective, missionObjects)
		end

		if not selected then
			selected, count, mechanic = genericObjective(lowerObjective)
		end

		return {
			Active = selected ~= nil,
			Supported = selected ~= nil,
			Objective = message,
			Mechanic = mechanic,
			Target = selected and selected.Part or nil,
			TargetName = selected and selected.Name or nil,
			TargetKind = selected and selected.Kind or nil,
			TargetPosition = selected and selected.Position or nil,
			TargetDistance = selected and selected.Distance or nil,
			TargetCount = count,
		}
	end

	function DungeonObjectives.Activate(state)
		local part = state and state.Target
		local kind = state and state.TargetKind
		local root = GameContext.GetRootPart()

		if
			not state
			or state.Active ~= true
			or not part
			or not part:IsA("BasePart")
			or not part:IsDescendantOf(Workspace)
			or not root
			or not root:IsDescendantOf(Workspace)
			or (kind ~= "RescueVillager" and kind ~= "ObjectiveTrigger")
		then
			return false, "objective_activation_unavailable"
		end

		local activationRange = math.clamp(part.Size.Magnitude * 0.5 + 5, 18, 30)
		local distance = (root.Position - part.Position).Magnitude

		if distance > activationRange then
			return false, "objective_target_too_far"
		end

		local now = os.clock()

		if now - (lastActivations[part] or 0) < 1 then
			return true, "objective_activation_pending"
		end

		lastActivations[part] = now

		local safeCFrame = root.CFrame
		local contactCFrame = CFrame.new(part.Position) * safeCFrame.Rotation
		local contacted, contactError = pcall(function()
			root.CFrame = contactCFrame
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			task.wait(0.2)

			if root.Parent then
				root.CFrame = safeCFrame
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		if not contacted then
			return false, "objective_contact_failed:" .. tostring(contactError)
		end

		return true, "objective_contacted"
	end

	function DungeonObjectives.Describe(missionState, missionObjects)
		local state = DungeonObjectives.GetState(missionState, missionObjects)

		return {
			Active = state.Active,
			Supported = state.Supported,
			Objective = state.Objective,
			Mechanic = state.Mechanic,
			TargetName = state.TargetName,
			TargetKind = state.TargetKind,
			TargetCount = state.TargetCount,
		}
	end

	return DungeonObjectives
end
