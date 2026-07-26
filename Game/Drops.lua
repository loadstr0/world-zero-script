return function(ctx)
	local Drops = {}

	local GameContext = ctx:Require("GameContext")
	local sharedDrops = nil

	local function resolveSharedDrops()
		if type(sharedDrops) == "table" then
			return sharedDrops
		end

		local moduleScript = GameContext.FindReplicated("Shared.Drops")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "drops_module_unavailable"
		end

		local ok, module = pcall(require, moduleScript)

		if not ok or type(module) ~= "table" then
			return nil, "drops_module_require_failed:" .. tostring(module)
		end

		sharedDrops = module
		return module
	end

	local function getHookEnvironment()
		local environment = _G

		pcall(function()
			if type(getgenv) == "function" then
				environment = getgenv()
			end
		end)

		return environment
	end

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

	function Drops.SetExtendedPetPickup(enabled)
		local module, moduleError = resolveSharedDrops()

		if not module then
			return false, moduleError
		elseif type(module.GetNearestCoinPosition) ~= "function" then
			return false, "pet_coin_locator_unavailable"
		end

		local environment = getHookEnvironment()
		local hookState = environment.__WZExtendedPetCoinPickup

		if type(hookState) ~= "table" or hookState.Module ~= module then
			hookState = {
				Module = module,
				Original = module.GetNearestCoinPosition,
				Enabled = enabled == true,
				Range = math.huge,
			}

			hookState.Wrapper = function(self, origin, requestedRange, ...)
				local range = tonumber(requestedRange) or 50

				if hookState.Enabled then
					range = math.max(range, tonumber(hookState.Range) or math.huge)
				end

				return hookState.Original(self, origin, range, ...)
			end

			environment.__WZExtendedPetCoinPickup = hookState
			module.GetNearestCoinPosition = hookState.Wrapper
		else
			hookState.Enabled = enabled == true

			if module.GetNearestCoinPosition ~= hookState.Wrapper then
				module.GetNearestCoinPosition = hookState.Wrapper
			end
		end

		return true
	end

	function Drops.GetExtendedPetPickupStatus()
		local hookState = getHookEnvironment().__WZExtendedPetCoinPickup

		return {
			Installed = type(hookState) == "table" and type(hookState.Wrapper) == "function",
			Enabled = type(hookState) == "table" and hookState.Enabled == true,
			Range = type(hookState) == "table" and hookState.Range or nil,
		}
	end

	function Drops.Describe()
		local folder = getFolder()
		local pickups = folder and Drops.List(math.huge) or {}
		local petPickup = Drops.GetExtendedPetPickupStatus()

		return {
			Available = folder ~= nil,
			Count = type(pickups) == "table" and #pickups or 0,
			CollectionDistance = 4,
			UsesGameProximityCollection = true,
			ExtendedPetPickupInstalled = petPickup.Installed,
			ExtendedPetPickupEnabled = petPickup.Enabled,
		}
	end

	return Drops
end
