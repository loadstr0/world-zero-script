return function(ctx)
	local Navigator = {}

	local GameContext = ctx:Require("GameContext")
	local PathfindingService = ctx.Services.PathfindingService
	local RunService = ctx.Services.RunService
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local currentPath = nil
	local waypoints = {}
	local waypointIndex = 0
	local destination = nil
	local blockedConnection = nil
	local lastCompute = 0
	local lastProgressAt = 0
	local lastProgressPosition = nil
	local lastStatus = "idle"
	local lastRoot = nil
	local lastHumanoid = nil
	local lastMovePosition = nil
	local lastMoveAt = 0
	local pathFailed = false
	local currentOwner = nil
	local currentMode = "Pathfinding"
	local flightConnection = nil
	local flightTarget = nil
	local flightOptions = nil
	local flightSafeTarget = nil
	local flightPlanTarget = nil
	local flightCruiseY = nil
	local flightPhase = nil
	local flightCollisionStates = setmetatable({}, { __mode = "k" })

	local function numberOption(value, fallback, minimum)
		local numeric = tonumber(value) or fallback

		if minimum then
			numeric = math.max(minimum, numeric)
		end

		return numeric
	end

	local function clearPath()
		if blockedConnection then
			blockedConnection:Disconnect()
			blockedConnection = nil
		end

		currentPath = nil
		table.clear(waypoints)
		waypointIndex = 0
		destination = nil
		pathFailed = false
	end

	local function issueMove(humanoid, position, force)
		local now = os.clock()
		local commandInterval = 6
		local changed = not lastMovePosition or (lastMovePosition - position).Magnitude >= 0.75

		if not force and humanoid == lastHumanoid and not changed and now - lastMoveAt < commandInterval then
			return false
		end

		humanoid:MoveTo(position)
		lastHumanoid = humanoid
		lastMovePosition = position
		lastMoveAt = now
		return true
	end

	local function getMovementParts()
		return GameContext.GetHumanoid(), GameContext.GetRootPart()
	end

	local function normalizeMode(value)
		if value == "Smooth Flight" or value == "Instant CFrame" then
			return value
		elseif value == "CFrame Step" then
			return "Smooth Flight"
		end

		return "Pathfinding"
	end

	local function setFlightCollision(enabled)
		local character = GameContext.GetCharacter()

		if enabled and character then
			for _, descendant in ipairs(character:GetDescendants()) do
				if descendant:IsA("BasePart") then
					if flightCollisionStates[descendant] == nil then
						flightCollisionStates[descendant] = descendant.CanCollide
					end

					descendant.CanCollide = false
				end
			end
		else
			for part, original in pairs(flightCollisionStates) do
				if part.Parent then
					part.CanCollide = original
				end

				flightCollisionStates[part] = nil
			end
		end
	end

	local function stopFlight()
		if flightConnection then
			flightConnection:Disconnect()
			flightConnection = nil
		end

		flightTarget = nil
		flightOptions = nil
		flightSafeTarget = nil
		flightPlanTarget = nil
		flightCruiseY = nil
		flightPhase = nil
		setFlightCollision(false)
	end

	local function getFlightRaycastParams()
		local filter = {}
		local character = GameContext.GetCharacter()

		if character then
			table.insert(filter, character)
		end

		for _, containerName in ipairs({ "Mobs", "Characters", "Pets", "Coins" }) do
			local container = Workspace:FindFirstChild(containerName)

			if container then
				table.insert(filter, container)
			end
		end

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = filter
		params.IgnoreWater = false

		pcall(function()
			params.RespectCanCollide = true
		end)

		return params
	end

	local function clampAboveGround(position, options)
		if options.FlightGroundSafety == false then
			return position
		end

		local clearance = numberOption(options.FlightGroundClearance, 3, 1)
		local probeHeight = math.max(clearance + 12, 16)
		local probeDepth = numberOption(options.FlightGroundProbeDepth, 512, 64)
		local result = nil

		pcall(function()
			result = Workspace:Raycast(
				position + Vector3.new(0, probeHeight, 0),
				Vector3.new(0, -(probeHeight + probeDepth), 0),
				getFlightRaycastParams()
			)
		end)

		if
			result
			and result.Position
			and result.Normal
			and result.Normal.Y >= 0.35
			and position.Y < result.Position.Y + clearance
		then
			return Vector3.new(position.X, result.Position.Y + clearance, position.Z)
		end

		return position
	end

	local function planFlight(root, targetPosition, options)
		flightSafeTarget = clampAboveGround(targetPosition, options)
		flightPlanTarget = targetPosition

		local flatOffset = Vector3.new(
			flightSafeTarget.X - root.Position.X,
			0,
			flightSafeTarget.Z - root.Position.Z
		)
		local routeThreshold = numberOption(options.FlightRouteThreshold, 35, 5)

		if options.FlightGroundSafety ~= false and flatOffset.Magnitude >= routeThreshold then
			local cruiseHeight = numberOption(options.FlightCruiseHeight, 35, 8)
			flightCruiseY = math.max(root.Position.Y, flightSafeTarget.Y) + cruiseHeight
			flightPhase = "ascent"
		else
			flightCruiseY = nil
			flightPhase = "approach"
		end
	end

	local function placeRoot(root, targetPosition, travelDistance, options)
		local offset = targetPosition - root.Position
		local distance = offset.Magnitude

		if distance <= 0.001 or travelDistance <= 0 then
			return true
		end

		local nextPosition = root.Position + offset.Unit * math.min(distance, travelDistance)
		nextPosition = clampAboveGround(nextPosition, options)
		local lookDirection = targetPosition - nextPosition
		local nextCFrame

		if lookDirection.Magnitude > 0.001 then
			nextCFrame = CFrame.lookAt(nextPosition, targetPosition)
		else
			nextCFrame = CFrame.new(nextPosition) * root.CFrame.Rotation
		end

		local moved, moveError = pcall(function()
			root.CFrame = nextCFrame

			if options.ZeroVelocity ~= false then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end)

		if not moved then
			lastStatus = "cframe_failed"
			return false, "cframe_move_failed:" .. tostring(moveError)
		end

		lastProgressPosition = nextPosition
		lastProgressAt = os.clock()
		lastMovePosition = nextPosition
		lastMoveAt = os.clock()
		return true, nil, nextPosition
	end

	local function moveInstantly(root, targetPosition, stopDistance, options)
		targetPosition = clampAboveGround(targetPosition, options)
		local distance = (targetPosition - root.Position).Magnitude

		if distance <= stopDistance then
			lastStatus = "in_range"
			return true, lastStatus
		end

		local moved, moveError = placeRoot(root, targetPosition, math.max(0, distance - stopDistance), options)

		if not moved then
			return false, moveError
		end

		destination = targetPosition
		lastStatus = "instant_cframe"
		return true, lastStatus
	end

	local function updateFlight(deltaTime)
		if currentMode ~= "Smooth Flight" or not flightTarget or not flightOptions then
			stopFlight()
			return
		end

		local _, root = getMovementParts()

		if not root then
			lastStatus = "movement_controller_unavailable"
			stopFlight()
			return
		end

		setFlightCollision(flightOptions.FlightNoclip ~= false)

		local stopDistance = numberOption(flightOptions.StopDistance, 0, 0)
		flightSafeTarget = clampAboveGround(flightTarget, flightOptions)
		local distance = (flightSafeTarget - root.Position).Magnitude

		if distance <= stopDistance then
			pcall(function()
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end)
			lastStatus = "in_range"
			return
		end

		local movementTarget = flightSafeTarget

		if flightPhase == "ascent" and flightCruiseY then
			if root.Position.Y >= flightCruiseY - 1 then
				flightPhase = "cruise"
			else
				movementTarget = Vector3.new(root.Position.X, flightCruiseY, root.Position.Z)
			end
		end

		if flightPhase == "cruise" and flightCruiseY then
			local horizontalOffset = Vector3.new(
				flightSafeTarget.X - root.Position.X,
				0,
				flightSafeTarget.Z - root.Position.Z
			)

			if horizontalOffset.Magnitude <= 2 then
				flightPhase = "descent"
			else
				movementTarget = Vector3.new(flightSafeTarget.X, flightCruiseY, flightSafeTarget.Z)
			end
		end

		local speed = numberOption(flightOptions.CFrameFlightSpeed, 90, 1)
		local waypointDistance = (movementTarget - root.Position).Magnitude
		local allowedDistance = waypointDistance

		if movementTarget == flightSafeTarget then
			allowedDistance = math.max(0, distance - stopDistance)
		end

		local travelDistance =
			math.min(allowedDistance, speed * math.max(tonumber(deltaTime) or 0, 0))
		local moved = placeRoot(root, movementTarget, travelDistance, flightOptions)

		if moved then
			lastStatus = "smooth_flight_" .. tostring(flightPhase or "approach")
		end
	end

	local function startFlight(targetPosition, options)
		local _, root = getMovementParts()
		local targetMoveThreshold = numberOption(options.TargetMoveThreshold, 10, 2)
		local needsPlan = not flightPlanTarget
			or not flightSafeTarget
			or (flightPlanTarget - targetPosition).Magnitude >= targetMoveThreshold

		flightTarget = targetPosition
		flightOptions = options
		destination = targetPosition

		if root and needsPlan then
			local flatDistance = Vector3.new(
				targetPosition.X - root.Position.X,
				0,
				targetPosition.Z - root.Position.Z
			).Magnitude

			if
				not flightPhase
				or (
					(flightPhase == "descent" or flightPhase == "approach")
					and flatDistance >= numberOption(options.FlightRouteThreshold, 35, 5)
				)
			then
				planFlight(root, targetPosition, options)
			else
				flightPlanTarget = targetPosition
				flightSafeTarget = clampAboveGround(targetPosition, options)

				if flightCruiseY then
					flightCruiseY = math.max(
						flightCruiseY,
						flightSafeTarget.Y + numberOption(options.FlightCruiseHeight, 35, 8)
					)
				end
			end
		elseif root then
			flightSafeTarget = clampAboveGround(targetPosition, options)
		end

		if not flightConnection then
			flightConnection = RunService.Heartbeat:Connect(updateFlight)
		end

		lastStatus = "smooth_flight_" .. tostring(flightPhase or "approach")
		return true, lastStatus
	end

	local function jump(humanoid)
		humanoid.Jump = true

		pcall(function()
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end)
	end

	local function computePath(targetPosition, options)
		local humanoid, root = getMovementParts()

		if not humanoid or not root then
			return false, "movement_controller_unavailable"
		end

		local path = nil
		local ok = pcall(function()
			path = PathfindingService:CreatePath({
				AgentRadius = options.AgentRadius or 2,
				AgentHeight = options.AgentHeight or 5,
				AgentCanJump = options.AutoJump ~= false,
				AgentCanClimb = options.AutoClimb == true,
				WaypointSpacing = options.WaypointSpacing or 4,
			})
			path:ComputeAsync(root.Position, targetPosition)
		end)

		lastCompute = os.clock()
		destination = targetPosition
		pathFailed = false

		if not ok or not path or path.Status ~= Enum.PathStatus.Success then
			if blockedConnection then
				blockedConnection:Disconnect()
				blockedConnection = nil
			end

			currentPath = nil
			table.clear(waypoints)
			waypointIndex = 0
			pathFailed = true
			lastStatus = "direct_fallback"
			issueMove(humanoid, targetPosition, true)
			return false, "path_unavailable"
		end

		if blockedConnection then
			blockedConnection:Disconnect()
		end

		currentPath = path
		waypoints = path:GetWaypoints()
		waypointIndex = #waypoints >= 2 and 2 or 1
		blockedConnection = path.Blocked:Connect(function(blockedIndex)
			if path == currentPath and blockedIndex >= math.max(waypointIndex, 1) then
				currentPath = nil
				pathFailed = false
				lastCompute = 0
				lastStatus = "path_blocked"
			end
		end)
		lastProgressAt = os.clock()
		lastProgressPosition = root.Position
		lastStatus = "path_ready"
		return true
	end

	local function needsRecompute(targetPosition, options)
		local now = os.clock()
		local movedThreshold = numberOption(options.TargetMoveThreshold, 8, 1)
		local repathInterval = numberOption(options.RepathInterval, 1.25, 0.2)
		local targetMoved = not destination or (destination - targetPosition).Magnitude >= movedThreshold

		if currentPath then
			return targetMoved and now - lastCompute >= repathInterval
		end

		if pathFailed then
			if
				destination
				and not targetMoved
				and now - lastCompute < numberOption(options.FailedPathRetryInterval, 3, repathInterval)
			then
				return false
			end

			return true
		end

		return true
	end

	function Navigator.MoveTo(targetPosition, options)
		options = options or {}

		if typeof(targetPosition) ~= "Vector3" then
			return false, "invalid_target_position"
		end

		local humanoid, root = getMovementParts()

		if not humanoid or not root then
			return false, "movement_controller_unavailable"
		end

		if root ~= lastRoot or humanoid ~= lastHumanoid then
			clearPath()
			stopFlight()
			lastRoot = root
			lastHumanoid = humanoid
			lastMovePosition = nil
			lastProgressPosition = root.Position
			lastProgressAt = os.clock()
		end

		local requestedOwner = tostring(options.Owner or "Default")
		local requestedMode = normalizeMode(options.MovementMode)

		if currentOwner ~= requestedOwner or currentMode ~= requestedMode then
			clearPath()
			stopFlight()
			currentOwner = requestedOwner
			currentMode = requestedMode
			lastMovePosition = nil
			lastProgressPosition = root.Position
			lastProgressAt = os.clock()
		end

		local stopDistance = numberOption(options.StopDistance, 0, 0)
		local distance = (root.Position - targetPosition).Magnitude

		if requestedMode == "Smooth Flight" then
			clearPath()
			currentOwner = requestedOwner
			currentMode = requestedMode
			return startFlight(targetPosition, options)
		elseif requestedMode == "Instant CFrame" then
			stopFlight()
			clearPath()
			currentOwner = requestedOwner
			currentMode = requestedMode
			return moveInstantly(root, targetPosition, stopDistance, options)
		end

		stopFlight()

		if distance <= stopDistance then
			if lastStatus ~= "in_range" then
				issueMove(humanoid, root.Position, true)
			end

			lastStatus = "in_range"
			return true, "in_range"
		end

		if needsRecompute(targetPosition, options) then
			computePath(targetPosition, options)
		end

		local waypoint = waypoints[waypointIndex]

		while waypoint and (root.Position - waypoint.Position).Magnitude <= (options.WaypointReachDistance or 3) do
			waypointIndex = waypointIndex + 1
			waypoint = waypoints[waypointIndex]
		end

		if waypoint then
			if options.AutoJump ~= false and waypoint.Action == Enum.PathWaypointAction.Jump then
				jump(humanoid)
			end

			issueMove(humanoid, waypoint.Position)
			lastStatus = "following_path"
		else
			issueMove(humanoid, targetPosition)
			lastStatus = "direct_fallback"
		end

		local now = os.clock()

		if not lastProgressPosition or (root.Position - lastProgressPosition).Magnitude >= 0.5 then
			lastProgressPosition = root.Position
			lastProgressAt = now
		elseif now - lastProgressAt >= numberOption(options.StuckTimeout, 1.4, 0.5) then
			if options.AutoJump ~= false then
				jump(humanoid)
			end

			if blockedConnection then
				blockedConnection:Disconnect()
				blockedConnection = nil
			end

			currentPath = nil
			pathFailed = false
			lastCompute = 0
			lastProgressAt = now
			lastProgressPosition = root.Position
			lastStatus = "stuck_recovery"
		end

		return true, lastStatus
	end

	function Navigator.RetreatFrom(threatPosition, distance, options)
		local _, root = getMovementParts()

		if not root then
			return false, "movement_controller_unavailable"
		end

		local offset = root.Position - threatPosition
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local direction = flatOffset.Magnitude > 0 and flatOffset.Unit or Vector3.new(0, 0, 1)
		local targetPosition = root.Position + direction * (tonumber(distance) or 30)
		options = options or {}
		options.StopDistance = 0

		return Navigator.MoveTo(targetPosition, options)
	end

	function Navigator.Stop()
		local humanoid, root = getMovementParts()

		if humanoid and root and lastStatus ~= "idle" then
			issueMove(humanoid, root.Position, true)
		end

		clearPath()
		stopFlight()
		lastMovePosition = nil
		currentOwner = nil
		currentMode = "Pathfinding"
		lastStatus = "idle"
	end

	function Navigator.GetState()
		return {
			Status = lastStatus,
			Waypoint = waypointIndex,
			WaypointCount = #waypoints,
			Destination = destination,
			Owner = currentOwner,
			Mode = currentMode,
			FlightPhase = flightPhase,
			FlightCruiseY = flightCruiseY,
			FlightGroundSafety = flightOptions and flightOptions.FlightGroundSafety ~= false or nil,
			PathFailed = pathFailed,
			LastMoveAge = lastMoveAt > 0 and os.clock() - lastMoveAt or nil,
		}
	end

	function Navigator.Describe()
		return {
			Available = PathfindingService ~= nil,
			UsesPathfinding = true,
			SupportsSmoothFlight = true,
			SupportsTerrainSafeFlight = true,
			SupportsInstantCFrame = true,
			CanJump = true,
			HasStuckRecovery = true,
		}
	end

	return Navigator
end
