return function()
	local Engine = {}

	local loops = {}
	local attempts = {}
	local statuses = {}

	local SLOT_ORDER = {
		"Primary",
		"Offhand",
		"Armor",
	}

	local function enabledForSlot(runtime, slotName)
		if slotName == "Armor" then
			return runtime.State:Get("Gear.AutoArmor", true)
		end

		return runtime.State:Get("Gear.AutoWeapons", true)
			and (slotName ~= "Offhand" or runtime.State:Get("Gear.AutoOffhand", true))
	end

	local function improvement(best, current)
		if not best then
			return 0
		end

		local bestScore = tonumber(best.EffectiveMaximumScore) or tonumber(best.MaximumScore) or 0
		local currentScore =
			current and (tonumber(current.EffectiveMaximumScore) or tonumber(current.MaximumScore)) or 0

		if not current or currentScore <= 0 then
			return math.huge
		end

		return ((bestScore - currentScore) / currentScore) * 100
	end

	local function setStatus(runtime, state)
		state.At = os.clock()
		statuses[runtime] = state
	end

	local function getAttempts(runtime, item)
		local runtimeAttempts = attempts[runtime]

		if not runtimeAttempts then
			runtimeAttempts = setmetatable({}, { __mode = "k" })
			attempts[runtime] = runtimeAttempts
		end

		return runtimeAttempts, tonumber(runtimeAttempts[item]) or 0
	end

	local function getLoadoutOptions(runtime)
		return {
			ReserveBestTradable = runtime.State:Get("Gear.ReserveBestTradable", true),
		}
	end

	function Engine.Scan(runtime)
		local loadout = runtime.GearAPI.GetBestLoadout(getLoadoutOptions(runtime))
		local result = {}

		for _, slotName in ipairs(SLOT_ORDER) do
			local slot = loadout[slotName] or {}
			local best = slot.Best
			local current = slot.Current

			result[slotName] = {
				Best = best,
				Current = current,
				Reserved = slot.Reserved,
				Improvement = improvement(best, current),
				Error = slot.Error,
			}
		end

		return result
	end

	local function canAfford(runtime, info, useCrystals)
		local balances, balanceError = runtime.GearAPI.GetBalances()

		if not balances then
			return false, balanceError
		end

		if useCrystals then
			local reserve = tonumber(runtime.State:Get("Gear.CrystalReserve", 0)) or 0

			if balances.Crystals - info.CrystalCost < reserve then
				return false, "crystal_reserve"
			end
		else
			local reserve = tonumber(runtime.State:Get("Gear.GoldReserve", 0)) or 0

			if balances.Gold - info.GoldCost < reserve then
				return false, "gold_reserve"
			end
		end

		return true
	end

	function Engine.Step(runtime)
		local scan = Engine.Scan(runtime)
		local minimumImprovement = tonumber(runtime.State:Get("Gear.MinimumImprovement", 0)) or 0

		for _, slotName in ipairs(SLOT_ORDER) do
			if enabledForSlot(runtime, slotName) then
				local slot = scan[slotName]
				local best = slot and slot.Best
				local current = slot and slot.Current
				local reserved = slot and slot.Reserved
				local replacingReserved = reserved
					and current
					and current.Item == reserved.Item
					and best
					and best.Item ~= reserved.Item
				local better = best
					and (
						best.Item == (current and current.Item)
						or slot.Improvement > minimumImprovement
						or replacingReserved
					)

				if better then
					local loadoutOptions = getLoadoutOptions(runtime)
					local autoUpgrade = runtime.State:Get("Gear.AutoUpgrade", false)
					local upgradeInfo = runtime.GearAPI.GetUpgradeInfo(best.Item)
					local isNewItem = best.Item ~= (current and current.Item)
					local waitUntilMaxed = runtime.State:Get("Gear.EquipOnlyMaxed", false)

					if
						isNewItem
						and runtime.State:Get("Gear.AutoEquip", true)
						and not waitUntilMaxed
					then
						local equipped, equipError =
							runtime.GearAPI.Equip(best.Item, slotName, loadoutOptions)

						setStatus(runtime, {
							Action = equipped and "Equip confirmed" or "Equip failed",
							Slot = slotName,
							Item = best.Name,
							Error = equipError,
						})
						return equipped, equipError
					end

					if autoUpgrade and upgradeInfo and not upgradeInfo.IsMaxed then
						local runtimeAttempts, count = getAttempts(runtime, best.Item)
						local maximumAttempts = tonumber(runtime.State:Get("Gear.MaxAttemptsPerItem", 50)) or 50

						if count >= maximumAttempts then
							setStatus(runtime, {
								Action = "Paused",
								Slot = slotName,
								Item = best.Name,
								Error = "attempt_limit_reached",
							})
							return false, "attempt_limit_reached"
						end

						local useCrystals = runtime.State:Get("Gear.UpgradeMode", "Gold attempts")
							== "Guaranteed crystals"
						local affordable, affordabilityError = canAfford(runtime, upgradeInfo, useCrystals)

						if not affordable then
							setStatus(runtime, {
								Action = "Waiting",
								Slot = slotName,
								Item = best.Name,
								Error = affordabilityError,
							})
							return false, affordabilityError
						end

						local requested, requestError =
							runtime.GearAPI.RequestUpgrade(best.Item, useCrystals, loadoutOptions)

						if requested then
							runtimeAttempts[best.Item] = count + 1
						end

						setStatus(runtime, {
							Action = requested and "Upgrade requested" or "Upgrade failed",
							Slot = slotName,
							Item = best.Name,
							Error = requestError,
							Attempt = count + (requested and 1 or 0),
						})
						return requested, requestError
					end

					if
						isNewItem
						and runtime.State:Get("Gear.AutoEquip", true)
						and (
							not waitUntilMaxed
							or not upgradeInfo
							or upgradeInfo.IsMaxed
						)
					then
						local equipped, equipError =
							runtime.GearAPI.Equip(best.Item, slotName, loadoutOptions)

						setStatus(runtime, {
							Action = equipped and "Equip requested" or "Equip failed",
							Slot = slotName,
							Item = best.Name,
							Error = equipError,
						})
						return equipped, equipError
					end
				end
			end
		end

		setStatus(runtime, {
			Action = "Loadout optimal",
		})
		return true, "loadout_optimal"
	end

	function Engine.GetStatus(runtime)
		return statuses[runtime]
	end

	function Engine.ResetAttempts(runtime)
		attempts[runtime] = nil
	end

	function Engine.Start(runtime)
		if loops[runtime] then
			return
		end

		local token = {}
		loops[runtime] = token

		task.spawn(function()
			while not runtime.Stopped and loops[runtime] == token and runtime.State:Get("Gear.Enabled", false) do
				local ok, stepError = pcall(Engine.Step, runtime)

				if not ok then
					setStatus(runtime, {
						Action = "Recovered",
						Error = tostring(stepError),
					})
				end

				task.wait(math.max(0.5, tonumber(runtime.State:Get("Gear.UpdateInterval", 2)) or 2))
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
		if runtime.State:Get("Gear.Enabled", false) then
			Engine.Start(runtime)
		else
			Engine.Stop(runtime)
		end
	end

	return Engine
end
