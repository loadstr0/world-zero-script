return function()
	local Engine = {}

	local loops = {}
	local statuses = {}

	local function setStatus(runtime, state)
		state.At = os.clock()
		statuses[runtime] = state
	end

	local function getProtectedGear(runtime)
		if not runtime.GearAPI or type(runtime.GearAPI.GetProtectedItems) ~= "function" then
			return {}
		end

		local ok, protected = pcall(runtime.GearAPI.GetProtectedItems, {
			ReserveBestTradable = runtime.State:Get("Gear.ReserveBestTradable", true),
		})

		if not ok or type(protected) ~= "table" then
			return {}
		end

		return protected
	end

	local function appendUnique(result, seen, descriptor)
		local item = descriptor and descriptor.Item

		if typeof(item) == "Instance" and item.Parent and not seen[item] then
			seen[item] = true
			table.insert(result, descriptor)
		end
	end

	function Engine.GetCandidates(runtime, inventoryPressure)
		local protectedGear = getProtectedGear(runtime)
		local preserveModified = runtime.State:Get("Loot.PreserveModified", true)
		local allowModifiedDominated = inventoryPressure == true
			and runtime.State:Get("Loot.AutoSellModifiedDominated", true)
		local result = {}
		local seen = {}
		local smartCount = 0

		if
			runtime.State:Get("Loot.SmartSellDominatedGear", true)
			and runtime.GearAPI
			and type(runtime.GearAPI.ListDominatedItems) == "function"
		then
			local dominated, dominatedError = runtime.GearAPI.ListDominatedItems({
				KeepPerCategory = runtime.State:Get("Loot.SmartSellKeepPerCategory", 2),
				ExcludeItems = protectedGear,
			})

			if not dominated then
				return nil, dominatedError
			end

			for _, gear in ipairs(dominated) do
				local item = gear.Item
				local protected = protectedGear[item]
					or runtime.InventoryAPI.IsProtected(
						item,
						preserveModified and not allowModifiedDominated
					)
				local descriptor = not protected and runtime.InventoryAPI.GetDescriptor(item) or nil

				if descriptor and descriptor.Price > 0 then
					descriptor.CleanupMode = "Dominated gear"
					descriptor.AllowModified = allowModifiedDominated
					descriptor.Category = gear.Category
					descriptor.CurrentScore = gear.CurrentScore
					descriptor.MaximumScore = gear.MaximumScore
					descriptor.DominatedBy = gear.DominatedBy
					appendUnique(result, seen, descriptor)
					smartCount += 1
				end
			end
		end

		if runtime.State:Get("Loot.SellByTierEnabled", false) then
			local thresholdCandidates, thresholdError = runtime.InventoryAPI.ListSellCandidates({
				MaxTier = runtime.State:Get("Loot.SellMaxTier", 1),
				MaxLevel = runtime.State:Get("Loot.SellMaxLevel", 10),
				PreserveModified = preserveModified,
				ExcludeItems = protectedGear,
			})

			if not thresholdCandidates then
				return nil, thresholdError
			end

			for _, descriptor in ipairs(thresholdCandidates) do
				descriptor.CleanupMode = descriptor.CleanupMode or "Tier/level rule"
				appendUnique(result, seen, descriptor)
			end
		end

		table.sort(result, function(a, b)
			local aSmart = a.CleanupMode == "Dominated gear"
			local bSmart = b.CleanupMode == "Dominated gear"

			if aSmart ~= bSmart then
				return aSmart
			elseif aSmart and bSmart and a.MaximumScore ~= b.MaximumScore then
				return a.MaximumScore < b.MaximumScore
			elseif a.Tier ~= b.Tier then
				return a.Tier < b.Tier
			elseif a.Level ~= b.Level then
				return a.Level < b.Level
			elseif a.Price ~= b.Price then
				return a.Price < b.Price
			end

			return a.Name < b.Name
		end)

		return result, nil, {
			Smart = smartCount,
			Total = #result,
		}
	end

	function Engine.Step(runtime)
		local capacity, capacityError = runtime.InventoryAPI.GetCapacity()

		if not capacity then
			setStatus(runtime, {
				Action = "Capacity unavailable",
				Error = capacityError,
			})
			return false, capacityError
		end

		local reserveSlots = math.max(0, tonumber(runtime.State:Get("Loot.AutoSellReserveSlots", 3)) or 3)

		if capacity.Remaining > reserveSlots then
			setStatus(runtime, {
				Action = "Space available",
				Remaining = capacity.Remaining,
				Capacity = capacity.Capacity,
			})
			return true, "inventory_has_space"
		end

		if not runtime.State:Get("Loot.AutoSellArmed", false) then
			setStatus(runtime, {
				Action = "Waiting for arm",
				Remaining = capacity.Remaining,
				Capacity = capacity.Capacity,
			})
			return false, "automatic_selling_not_armed"
		end

		local candidates, candidateError, candidateSummary = Engine.GetCandidates(runtime, true)

		if not candidates then
			setStatus(runtime, {
				Action = "Selection failed",
				Error = candidateError,
			})
			return false, candidateError
		elseif #candidates == 0 then
			setStatus(runtime, {
				Action = "Inventory blocked",
				Remaining = capacity.Remaining,
				Capacity = capacity.Capacity,
				Error = "no_safe_sell_candidates",
			})
			return false, "no_safe_sell_candidates"
		end

		local batchSize = math.max(1, tonumber(runtime.State:Get("Loot.AutoSellBatchSize", 5)) or 5)
		local batch = {}

		for index = 1, math.min(batchSize, #candidates) do
			table.insert(batch, candidates[index])
		end

		local gold, soldOrError = runtime.InventoryAPI.Sell(
			batch,
			runtime.State:Get("Loot.PreserveModified", true),
			getProtectedGear(runtime)
		)

		local cleanupStatus = {
			Action = gold and "Sold safe items" or "Sell failed",
			Sold = gold and soldOrError or 0,
			Gold = gold,
			SmartCandidates = candidateSummary and candidateSummary.Smart or 0,
			Remaining = capacity.Remaining,
			Capacity = capacity.Capacity,
		}

		if gold == nil then
			cleanupStatus.Error = soldOrError
		end

		setStatus(runtime, cleanupStatus)

		return gold ~= nil, gold and "inventory_cleanup_requested" or soldOrError
	end

	function Engine.GetStatus(runtime)
		return statuses[runtime]
	end

	function Engine.Start(runtime)
		if loops[runtime] then
			return
		end

		local token = {}
		loops[runtime] = token

		task.spawn(function()
			while
				not runtime.Stopped
				and loops[runtime] == token
				and runtime.State:Get("Loot.AutoSellEnabled", false)
			do
				local ok, stepError = pcall(Engine.Step, runtime)

				if not ok then
					setStatus(runtime, {
						Action = "Recovered",
						Error = tostring(stepError),
					})
				end

				task.wait(math.max(1, tonumber(runtime.State:Get("Loot.AutoSellInterval", 5)) or 5))
			end

			if loops[runtime] == token then
				loops[runtime] = nil
			end
		end)
	end

	function Engine.Stop(runtime)
		loops[runtime] = nil
	end

	function Engine.Reconcile(runtime)
		if runtime.State:Get("Loot.AutoSellEnabled", false) then
			Engine.Start(runtime)
		else
			Engine.Stop(runtime)
		end
	end

	return Engine
end
