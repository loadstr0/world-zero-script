return function(ctx)
	local DungeonRoutes = {}

	local Players = ctx.Services.Players
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")

	local function getPart(instance)
		if not instance then
			return nil
		elseif instance:IsA("BasePart") then
			return instance
		elseif instance:IsA("Attachment") then
			return instance.Parent
		elseif instance:IsA("Model") then
			return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)
		end

		return instance:FindFirstChildWhichIsA("BasePart", true)
	end

	local function getRoot()
		local player = Players.LocalPlayer
		local character = player and player.Character
		return character
			and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
			or nil
	end

	local function isDirectRouteBlocked(root, targetPosition)
		local offset = targetPosition - root.Position

		if offset.Magnitude <= 8 then
			return false
		end

		local filter = { root.Parent }

		for _, containerName in ipairs({ "Mobs", "Characters", "Pets" }) do
			local container = Workspace:FindFirstChild(containerName)

			if container then
				table.insert(filter, container)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		params.IgnoreWater = true

		local result = Workspace:Raycast(root.Position, offset, params)
		return result ~= nil and (result.Position - targetPosition).Magnitude > 6
	end

	local function collectRouteParts(missionObjects, targetPosition)
		local checkpoints = {}
		local gates = {}

		for _, instance in ipairs(missionObjects:GetDescendants()) do
			local part = getPart(instance)

			if part then
				if
					instance:IsA("BasePart")
					and instance.Parent
					and instance.Parent.Name == "Checkpoints"
					and string.match(instance.Name, "^Checkpoint%d+$")
				then
					table.insert(checkpoints, part)
				elseif
					instance:IsA("Model")
					and string.find(string.lower(instance.Name), "gate", 1, true)
				then
					table.insert(gates, part)
				end
			end
		end

		table.sort(checkpoints, function(a, b)
			return (a.Position - targetPosition).Magnitude < (b.Position - targetPosition).Magnitude
		end)

		local checkpoint = checkpoints[1]

		if checkpoint then
			table.sort(gates, function(a, b)
				return (a.Position - checkpoint.Position).Magnitude < (b.Position - checkpoint.Position).Magnitude
			end)
		end

		return checkpoint, gates[1]
	end

	function DungeonRoutes.GetCombatRoute(dungeonState, descriptor)
		local root = getRoot()
		local targetPosition = descriptor and descriptor.Position
		local missionObjects = dungeonState and dungeonState.MissionObjects

		if
			not dungeonState
			or dungeonState.Active ~= true
			or dungeonState.Phase ~= "Combat"
			or not root
			or typeof(targetPosition) ~= "Vector3"
			or not missionObjects
		then
			return nil
		end

		local verticalDrop = root.Position.Y - targetPosition.Y

		if verticalDrop < 24 or not isDirectRouteBlocked(root, targetPosition) then
			return nil
		end

		local checkpoint, gate = collectRouteParts(missionObjects, targetPosition)

		if not checkpoint then
			return nil
		end

		local targetPart = checkpoint
		local kind = "InteriorCheckpoint"

		if gate and (root.Position - gate.Position).Magnitude > 12 then
			targetPart = gate
			kind = "InteriorGate"
		end

		return {
			Kind = kind,
			Name = targetPart.Name,
			Position = targetPart.Position,
			StopDistance = 7,
			FlightGroundSafety = false,
			FlightCruiseHeight = 6,
			FlightNoclip = true,
		}
	end

	return DungeonRoutes
end
