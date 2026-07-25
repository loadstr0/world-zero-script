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

		local ok, protected = pcall(runtime.GearAPI.GetProtectedItems)

		if not ok or type(protected) ~= "table" then
			return {}
		end

		return protected
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

		local protectedGear = getProtectedGear(runtime)
		local candidates, candidateError = runtime.InventoryAPI.ListSellCandidates({
			MaxTier = runtime.State:Get("Loot.SellMaxTier", 1),
			MaxLevel = runtime.State:Get("Loot.SellMaxLevel", 10),
			PreserveModified = runtime.State:Get("Loot.PreserveModified", true),
			ExcludeItems = protectedGear,
		})

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

		setStatus(runtime, {
			Action = gold and "Sold safe items" or "Sell failed",
			Sold = gold and soldOrError or 0,
			Gold = gold,
			Remaining = capacity.Remaining,
			Capacity = capacity.Capacity,
			Error = gold and nil or soldOrError,
		})

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
