return function(ctx)
	local DungeonRoutes = {}

	local Players = ctx.Services.Players
	local PathfindingService = ctx.Services.PathfindingService
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local progressionSession = nil

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

	local function getEntranceGuide(root, targetPart)
		if not progressionSession or not PathfindingService or not targetPart then
			return nil
		end

		if progressionSession.EntranceTarget ~= targetPart then
			progressionSession.EntranceTarget = targetPart
			progressionSession.EntranceGuide = nil
			progressionSession.EntranceChecked = false
			progressionSession.EntranceComplete = false
		end

		if progressionSession.EntranceComplete then
			return nil
		elseif progressionSession.EntranceGuide then
			if (root.Position - progressionSession.EntranceGuide).Magnitude <= 5 then
				progressionSession.EntranceComplete = true
				progressionSession.EntranceGuide = nil
				return nil
			end

			return progressionSession.EntranceGuide
		elseif progressionSession.EntranceChecked then
			return nil
		end

		progressionSession.EntranceChecked = true

		local path
		local computed = pcall(function()
			path = PathfindingService:CreatePath({
				AgentRadius = 2,
				AgentHeight = 5,
				AgentCanJump = true,
				AgentCanClimb = true,
				WaypointSpacing = 5,
			})
			path:ComputeAsync(root.Position, targetPart.Position)
		end)

		if not computed or not path or path.Status ~= Enum.PathStatus.Success then
			return nil
		end

		for index, waypoint in ipairs(path:GetWaypoints()) do
			if
				index > 1
				and root.Position.Y - waypoint.Position.Y >= 15
			then
				progressionSession.EntranceGuide =
					waypoint.Position + Vector3.new(0, 3, 0)
				return progressionSession.EntranceGuide
			end
		end

		return nil
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
		local distance = (root.Position - targetPosition).Magnitude
		local directRouteBlocked = isDirectRouteBlocked(root, targetPosition)

		if distance <= 32 then
			return nil
		end

		if verticalDrop < 24 then
			if
				root.Position.Y >= 10
				and targetPosition.Y >= 10
				and not directRouteBlocked
			then
				return nil
			end

			return {
				Kind = "InteriorApproach",
				Name = descriptor.Name or "Dungeon target",
				Position = targetPosition,
				StopDistance = 28,
				FlightGroundSafety = false,
				FlightCruiseHeight = 6,
				FlightNoclip = true,
			}
		end

		if not directRouteBlocked then
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

	function DungeonRoutes.GetProgressionRoute(dungeonState)
		local root = getRoot()
		local missionObjects = dungeonState and dungeonState.MissionObjects
		local checkpointNumber = dungeonState
			and string.match(tostring(dungeonState.ProgressionName or ""), "^Checkpoint(%d+)$")

		if
			not root
			or not missionObjects
			or dungeonState.Phase ~= "Progression"
			or not checkpointNumber
		then
			return nil
		end

		local sessionKey = table.concat({
			tostring(dungeonState.MissionID),
			tostring(checkpointNumber),
		}, ":")

		if
			not progressionSession
			or progressionSession.Key ~= sessionKey
			or progressionSession.Character ~= root.Parent
		then
			progressionSession = {
				Key = sessionKey,
				Character = root.Parent,
				Step = 1,
			}
		end

		local room = missionObjects:FindFirstChild("Room" .. checkpointNumber .. "Trigger", true)
		local gateModel = missionObjects:FindFirstChild("Gate" .. checkpointNumber, true)
		local gate = getPart(gateModel)
		local checkpoint = getPart(dungeonState.ProgressionTarget)
			or getPart(missionObjects:FindFirstChild("Checkpoint" .. checkpointNumber, true))
		local route = {}

		if getPart(room) then
			table.insert(route, {
				Kind = "DungeonRoom",
				Name = room.Name,
				Part = getPart(room),
				StopDistance = 14,
			})
		end

		if gate then
			table.insert(route, {
				Kind = "DungeonGate",
				Name = gateModel.Name,
				Part = gate,
				StopDistance = 10,
			})
		end

		if checkpoint then
			table.insert(route, {
				Kind = "DungeonCheckpoint",
				Name = checkpoint.Name,
				Part = checkpoint,
				StopDistance = 8,
			})
		end

		-- A respawn, module refresh, or server-driven room transition can place the
		-- character beyond an earlier marker before this local session observes it.
		-- Resume from the closest forward marker so the route never tries to fly
		-- backward through closed dungeon geometry.
		local nearestIndex = nil
		local nearestDistance = math.huge

		for index = progressionSession.Step, #route do
			local distance = (root.Position - route[index].Part.Position).Magnitude

			if distance < nearestDistance then
				nearestIndex = index
				nearestDistance = distance
			end
		end

		if nearestIndex and nearestIndex > progressionSession.Step then
			progressionSession.Step = nearestIndex
		end

		while progressionSession.Step <= #route do
			local step = route[progressionSession.Step]

			if (root.Position - step.Part.Position).Magnitude > step.StopDistance + 4 then
				break
			end

			progressionSession.Step = progressionSession.Step + 1
		end

		local step = route[progressionSession.Step]

		if not step then
			return nil
		end

		local guide = step.Kind == "DungeonRoom"
				and getEntranceGuide(root, step.Part)
			or nil

		if guide then
			return {
				Kind = "DungeonEntrance",
				Name = step.Name .. " entrance",
				Position = guide,
				StopDistance = 2,
				MovementMode = "Smooth Flight",
				FlightGroundSafety = false,
				FlightCruiseHeight = 4,
				FlightNoclip = true,
			}
		end

		return {
			Kind = step.Kind,
			Name = step.Name,
			Position = step.Part.Position,
			StopDistance = step.StopDistance,
			MovementMode = "Pathfinding",
			FlightGroundSafety = false,
			FlightCruiseHeight = 6,
			FlightNoclip = true,
		}
	end

	return DungeonRoutes
end
