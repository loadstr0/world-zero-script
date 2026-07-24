return function(ctx)
	local Drops = {}

	local GameContext = ctx:Require("GameContext")

	local function getFolder()
		return workspace:FindFirstChild("Coins")
	end

	local function getRoot()
		return GameContext.GetRootPart()
	end

	local function isPickup(instance)
		return instance and instance.Parent and instance:IsA("BasePart") and instance.Name == "CoinPart"
	end

	function Drops.List(range)
		local folder = getFolder()
		local root = getRoot()

		if not folder then
			return {}, "coins_folder_unavailable"
		end

		if not root then
			return {}, "character_root_unavailable"
		end

		local maximum = tonumber(range) or math.huge
		local pickups = {}

		for _, child in ipairs(folder:GetChildren()) do
			if isPickup(child) then
				local distance = (child.Position - root.Position).Magnitude

				if distance <= maximum then
					table.insert(pickups, {
						Part = child,
						Position = child.Position,
						Distance = distance,
						Kind = "Drop",
						Name = "Dropped item",
					})
				end
			end
		end

		table.sort(pickups, function(a, b)
			return a.Distance < b.Distance
		end)

		return pickups
	end

	function Drops.GetNearest(range)
		local pickups, listError = Drops.List(range)

		if #pickups == 0 then
			return nil, listError or "no_drops_in_range"
		end

		return pickups[1]
	end

	function Drops.IsValid(descriptor)
		return descriptor and isPickup(descriptor.Part)
	end

	function Drops.Describe()
		local folder = getFolder()
		local pickups = folder and Drops.List(math.huge) or {}

		return {
			Available = folder ~= nil,
			Count = type(pickups) == "table" and #pickups or 0,
			CollectionDistance = 4,
			UsesGameProximityCollection = true,
		}
	end

	return Drops
end
