return function(ctx)
	local Hazards = {}

	local GameContext = ctx:Require("GameContext")
	local Workspace = ctx.Services.Workspace

	local INDICATOR_PARTS = {
		RadialIndicator = {
			PartName = "CircleIndicator",
			Shape = "Circle",
		},
		RectangularIndicator = {
			PartName = "BoxIndicator",
			Shape = "Box",
		},
		ConeIndicator = {
			PartName = "ConeIndicator",
			Shape = "Box",
		},
		BlastIndicator = {
			PartName = "Part",
			Shape = "Circle",
		},
		AlienBlastIndicator = {
			PartName = "Part",
			Shape = "Circle",
		},
	}

	local function isHostileColor(part)
		local surface = part:FindFirstChildOfClass("SurfaceGui")
		local frame = surface and surface:FindFirstChild("Frame")
		local circle = frame and frame:FindFirstChild("Circle")

		if not circle or not circle:IsA("ImageLabel") then
			return true
		end

		local color = circle.ImageColor3
		return color.R >= color.G * 0.85
	end

	local function makeDescriptor(model, definition)
		local part = model:FindFirstChild(definition.PartName, true)

		if not part or not part:IsA("BasePart") or not isHostileColor(part) then
			return nil
		end

		return {
			Instance = model,
			Part = part,
			Name = model.Name,
			Shape = definition.Shape,
			Position = part.Position,
			Size = part.Size,
			CFrame = part.CFrame,
		}
	end

	local function signedClearance(hazard, position, padding, projected)
		local part = hazard.Part

		if not part or not part.Parent then
			return math.huge
		end

		local localPosition = part.CFrame:PointToObjectSpace(position)
		local verticalLimit = math.max(10, part.Size.Y * 0.5 + 6)

		if not projected and math.abs(localPosition.Y) > verticalLimit then
			return math.huge
		end

		padding = math.max(0, tonumber(padding) or 0)

		if hazard.Shape == "Circle" then
			local radius = math.max(part.Size.X, part.Size.Z) * 0.5 + padding
			return Vector2.new(localPosition.X, localPosition.Z).Magnitude - radius
		end

		local halfX = part.Size.X * 0.5 + padding
		local halfZ = part.Size.Z * 0.5 + padding
		local outsideX = math.abs(localPosition.X) - halfX
		local outsideZ = math.abs(localPosition.Z) - halfZ

		if outsideX <= 0 and outsideZ <= 0 then
			return -math.min(-outsideX, -outsideZ)
		end

		return Vector2.new(math.max(0, outsideX), math.max(0, outsideZ)).Magnitude
	end

	local function getRaycastParams(extraExclusions)
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

		for _, instance in ipairs(extraExclusions or {}) do
			table.insert(filter, instance)
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

	local function hasClearRoute(origin, destination, hazards)
		local exclusions = {}

		for _, hazard in ipairs(hazards) do
			table.insert(exclusions, hazard.Instance)
		end

		local offset = destination - origin
		local horizontal = Vector3.new(offset.X, 0, offset.Z)

		if horizontal.Magnitude <= 1 then
			return true
		end

		local result = nil

		pcall(function()
			result = Workspace:Raycast(
				origin + Vector3.new(0, 2, 0),
				horizontal,
				getRaycastParams(exclusions)
			)
		end)

		return not result or (result.Position - origin).Magnitude >= horizontal.Magnitude - 2
	end

	local function groundCandidate(position, referenceY, hazards)
		local exclusions = {}

		for _, hazard in ipairs(hazards) do
			table.insert(exclusions, hazard.Instance)
		end

		local result = nil

		pcall(function()
			result = Workspace:Raycast(
				Vector3.new(position.X, referenceY + 15, position.Z),
				Vector3.new(0, -55, 0),
				getRaycastParams(exclusions)
			)
		end)

		if result and result.Position and result.Normal and result.Normal.Y >= 0.35 then
			return Vector3.new(position.X, math.max(referenceY, result.Position.Y + 3), position.Z)
		end

		return Vector3.new(position.X, referenceY, position.Z)
	end

	function Hazards.List()
		local result = {}

		for _, child in ipairs(Workspace:GetChildren()) do
			local definition = INDICATOR_PARTS[child.Name]

			if definition and child:IsA("Model") then
				local descriptor = makeDescriptor(child, definition)

				if descriptor then
					table.insert(result, descriptor)
				end
			end
		end

		return result
	end

	function Hazards.GetState(position, padding, options)
		if typeof(position) ~= "Vector3" then
			local root = GameContext.GetRootPart()
			position = root and root.Position or nil
		end

		if typeof(position) ~= "Vector3" then
			return nil, "character_unavailable"
		end

		local hazards = Hazards.List()
		local inside = {}
		local nearest = nil
		local nearestClearance = math.huge
		local projected = type(options) == "table" and options.Projected == true

		for _, hazard in ipairs(hazards) do
			local clearance = signedClearance(hazard, position, padding, projected)
			hazard.Clearance = clearance

			if clearance < nearestClearance then
				nearest = hazard
				nearestClearance = clearance
			end

			if clearance <= 0 then
				table.insert(inside, hazard)
			end
		end

		return {
			Count = #hazards,
			InsideCount = #inside,
			Hazards = hazards,
			Inside = inside,
			Nearest = nearest,
			NearestClearance = nearestClearance,
		}
	end

	function Hazards.FindEscape(position, state, padding, escapeBuffer, options)
		if typeof(position) ~= "Vector3" or type(state) ~= "table" or #state.Inside == 0 then
			return nil, "not_inside_hazard"
		end

		padding = math.max(0, tonumber(padding) or 4)
		escapeBuffer = math.max(4, tonumber(escapeBuffer) or 10)
		local projected = type(options) == "table" and options.Projected == true
		local requiredRadius = 12

		for _, hazard in ipairs(state.Inside) do
			requiredRadius = math.max(
				requiredRadius,
				math.min(70, math.max(hazard.Size.X, hazard.Size.Z) * 0.5 + padding + escapeBuffer)
			)
		end

		local radii = {
			math.min(25, requiredRadius),
			math.min(45, math.max(25, requiredRadius)),
			math.min(70, math.max(45, requiredRadius)),
		}
		local best = nil
		local bestSafety = -math.huge

		for _, radius in ipairs(radii) do
			local foundAtRadius = false

			for index = 0, 23 do
				local angle = (math.pi * 2 * index) / 24
				local rawCandidate = position
					+ Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
				local candidate = projected
						and rawCandidate
					or groundCandidate(rawCandidate, position.Y, state.Hazards)
				local minimumClearance = math.huge

				for _, hazard in ipairs(state.Hazards) do
					minimumClearance =
						math.min(minimumClearance, signedClearance(hazard, candidate, padding, projected))
				end

				if minimumClearance > 0 and hasClearRoute(position, candidate, state.Hazards) then
					foundAtRadius = true

					if minimumClearance > bestSafety then
						best = candidate
						bestSafety = minimumClearance
					end
				end
			end

			if foundAtRadius then
				break
			end
		end

		if not best then
			local nearest = state.Nearest
			local offset = nearest and (position - nearest.Position) or Vector3.new(0, 0, 1)
			local flat = Vector3.new(offset.X, 0, offset.Z)
			local direction = flat.Magnitude > 0.01 and flat.Unit or Vector3.new(0, 0, 1)
			local rawFallback = position + direction * math.min(70, requiredRadius)
			best = projected
					and rawFallback
				or groundCandidate(rawFallback, position.Y, state.Hazards)
		end

		return best, nil, bestSafety
	end

	function Hazards.Describe()
		return {
			Available = Workspace ~= nil,
			SupportsRadial = true,
			SupportsRectangular = true,
			SupportsCone = true,
			UsesLiveIndicatorGeometry = true,
			SupportsProjectedAirSafety = true,
		}
	end

	return Hazards
end
