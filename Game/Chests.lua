return function(ctx)
	local Chests = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Chests")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil
		end

		local ok, module = pcall(require, moduleScript)

		if ok and type(module) == "table" then
			cachedModule = module
		end

		return cachedModule
	end

	local function getPosition(instance)
		if not instance or not instance.Parent then
			return nil
		end

		if instance:IsA("BasePart") then
			return instance.Position
		end

		if instance:IsA("Model") then
			local primary = instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart", true)

			return primary and primary.Position or nil
		end

		return nil
	end

	local function isChestCandidate(instance)
		if not instance or not instance.Parent then
			return false
		end

		if instance:FindFirstChild("WorldChestID") then
			local module = resolve()
			local profile = Profile.Get()

			if module and profile and type(module.ChestAvailable) == "function" then
				local ok, available = pcall(module.ChestAvailable, module, profile, instance)

				if ok and available == false then
					return false
				end
			end

			return getPosition(instance) ~= nil
		end

		return instance.Parent == workspace
			and instance:IsA("Model")
			and string.find(string.lower(instance.Name), "chest", 1, true) ~= nil
			and instance.Name ~= "AuraChest"
			and getPosition(instance) ~= nil
	end

	local function appendCandidate(result, seen, instance, root, maximum)
		if seen[instance] or not isChestCandidate(instance) then
			return
		end

		local position = getPosition(instance)

		if not position then
			return
		end

		local distance = (position - root.Position).Magnitude

		if distance > maximum then
			return
		end

		seen[instance] = true
		table.insert(result, {
			Instance = instance,
			Position = position,
			Distance = distance,
			Kind = "Chest",
			Name = instance.Name,
			IsWorldChest = instance:FindFirstChild("WorldChestID") ~= nil,
		})
	end

	function Chests.List(range)
		local root = GameContext.GetRootPart()

		if not root then
			return {}, "character_root_unavailable"
		end

		local maximum = tonumber(range) or math.huge
		local result = {}
		local seen = {}

		for _, child in ipairs(workspace:GetChildren()) do
			appendCandidate(result, seen, child, root, maximum)
		end

		local spawns = workspace:FindFirstChild("ChestSpawns")

		if spawns then
			for _, descendant in ipairs(spawns:GetDescendants()) do
				if descendant:FindFirstChild("WorldChestID") then
					appendCandidate(result, seen, descendant, root, maximum)
				end
			end
		end

		table.sort(result, function(a, b)
			return a.Distance < b.Distance
		end)

		return result
	end

	function Chests.GetNearest(range)
		local chests, listError = Chests.List(range)

		if #chests == 0 then
			return nil, listError or "no_chests_in_range"
		end

		return chests[1]
	end

	function Chests.IsValid(descriptor)
		return descriptor and isChestCandidate(descriptor.Instance)
	end

	function Chests.Describe()
		local chests = Chests.List(math.huge)
		local module = resolve()

		return {
			Available = module ~= nil,
			Count = type(chests) == "table" and #chests or 0,
			SpawnedChestOpenDistance = 10,
			UsesGameProximityOpen = true,
		}
	end

	return Chests
end
