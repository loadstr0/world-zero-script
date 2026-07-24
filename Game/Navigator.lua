return function(ctx)
	local Navigator = {}

	local GameContext = ctx:Require("GameContext")
	local PathfindingService = ctx.Services.PathfindingService
	local currentPath = nil
	local waypoints = {}
	local waypointIndex = 0
	local destination = nil
	local blockedConnection = nil
	local lastCompute = 0
	local lastProgressAt = 0
	local lastProgressPosition = nil
	local lastStatus = "idle"

	local function clearPath()
		if blockedConnection then
			blockedConnection:Disconnect()
			blockedConnection = nil
		end

		currentPath = nil
		table.clear(waypoints)
		waypointIndex = 0
		destination = nil
	end

	local function getMovementParts()
		return GameContext.GetHumanoid(), GameContext.GetRootPart()
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

		if
			not ok
			or not path
			or path.Status ~= Enum.PathStatus.Success
		then
			if blockedConnection then
				blockedConnection:Disconnect()
				blockedConnection = nil
			end

			currentPath = nil
			table.clear(waypoints)
			waypointIndex = 0
			lastStatus = "direct_fallback"
			humanoid:MoveTo(targetPosition)
			return false, "path_unavailable"
		end

		if blockedConnection then
			blockedConnection:Disconnect()
		end

		currentPath = path
		waypoints = path:GetWaypoints()
		waypointIndex = math.min(2, #waypoints)
		blockedConnection = path.Blocked:Connect(function(blockedIndex)
			if
				path == currentPath
				and blockedIndex >= waypointIndex
			then
				currentPath = nil
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
		if not currentPath or waypointIndex <= 0 or waypointIndex > #waypoints then
			if
				destination
				and (destination - targetPosition).Magnitude
					< (options.TargetMoveThreshold or 8)
				and os.clock() - lastCompute
					< (options.RepathInterval or 1.25)
			then
				return false
			end

			return true
		end

		if
			not destination
			or (destination - targetPosition).Magnitude
				>= (options.TargetMoveThreshold or 8)
		then
			return true
		end

		return os.clock() - lastCompute
			>= (options.RepathInterval or 1.25)
	end

	function Navigator.MoveTo(targetPosition, options)
		options = options or {}
		local humanoid, root = getMovementParts()

		if not humanoid or not root then
			return false, "movement_controller_unavailable"
		end

		local stopDistance = tonumber(options.StopDistance) or 0
		local distance = (root.Position - targetPosition).Magnitude

		if distance <= stopDistance then
			humanoid:MoveTo(root.Position)
			lastStatus = "in_range"
			return true, "in_range"
		end

		if needsRecompute(targetPosition, options) then
			computePath(targetPosition, options)
		end

		local waypoint = waypoints[waypointIndex]

		while
			waypoint
			and (root.Position - waypoint.Position).Magnitude
				<= (options.WaypointReachDistance or 3)
		do
			waypointIndex = waypointIndex + 1
			waypoint = waypoints[waypointIndex]
		end

		if waypoint then
			if
				options.AutoJump ~= false
				and waypoint.Action == Enum.PathWaypointAction.Jump
			then
				jump(humanoid)
			end

			humanoid:MoveTo(waypoint.Position)
			lastStatus = "following_path"
		else
			humanoid:MoveTo(targetPosition)
			lastStatus = "direct_fallback"
		end

		local now = os.clock()

		if
			not lastProgressPosition
			or (root.Position - lastProgressPosition).Magnitude >= 1
		then
			lastProgressPosition = root.Position
			lastProgressAt = now
		elseif
			now - lastProgressAt
				>= (options.StuckTimeout or 0.9)
		then
			if options.AutoJump ~= false then
				jump(humanoid)
			end

			if blockedConnection then
				blockedConnection:Disconnect()
				blockedConnection = nil
			end

			currentPath = nil
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
		local direction = flatOffset.Magnitude > 0
				and flatOffset.Unit
			or Vector3.new(0, 0, 1)
		local targetPosition =
			root.Position + direction * (tonumber(distance) or 30)
		options = options or {}
		options.StopDistance = 0

		return Navigator.MoveTo(targetPosition, options)
	end

	function Navigator.Stop()
		local humanoid, root = getMovementParts()

		if humanoid and root then
			humanoid:MoveTo(root.Position)
		end

		clearPath()
		lastStatus = "idle"
	end

	function Navigator.GetState()
		return {
			Status = lastStatus,
			Waypoint = waypointIndex,
			WaypointCount = #waypoints,
			Destination = destination,
		}
	end

	function Navigator.Describe()
		return {
			Available = PathfindingService ~= nil,
			UsesPathfinding = true,
			CanJump = true,
			HasStuckRecovery = true,
		}
	end

	return Navigator
end
