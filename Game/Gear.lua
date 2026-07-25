return function(ctx)
	local Gear = {}

	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players
	local modules = {}

	local SLOT_ORDER = {
		"Primary",
		"Offhand",
		"Armor",
	}

	local SLOT_STAT = {
		Primary = "Attack",
		Armor = "Defense",
	}

	local function resolve(path, key)
		if type(modules[key]) == "table" then
			return modules[key]
		end

		local moduleScript = GameContext.FindReplicated(path)

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "module_not_found:" .. path
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "module_require_failed:" .. path .. ":" .. tostring(result)
		end

		modules[key] = result
		return result
	end

	local function getModules()
		local inventory, inventoryError = resolve("Shared.Inventory", "Inventory")

		if not inventory then
			return nil, inventoryError
		end

		local upgrade, upgradeError = resolve("Shared.ItemUpgrade", "ItemUpgrade")

		if not upgrade then
			return nil, upgradeError
		end

		local combat, combatError = resolve("Shared.Combat", "Combat")

		if not combat then
			return nil, combatError
		end

		local profile, profileError = resolve("Shared.Profile", "Profile")

		if not profile then
			return nil, profileError
		end

		return {
			Inventory = inventory,
			ItemUpgrade = upgrade,
			Combat = combat,
			Profile = profile,
		}
	end

	local function getContext()
		local resolved, resolveError = getModules()

		if not resolved then
			return nil, resolveError
		end

		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local profileOk, profile = pcall(resolved.Profile.GetProfile, resolved.Profile, player)
		local equipsOk, equips = pcall(resolved.Profile.GetPlayerEquips, resolved.Profile, player)

		if not profileOk or typeof(profile) ~= "Instance" then
			return nil, "player_profile_unavailable"
		elseif not equipsOk or typeof(equips) ~= "Instance" then
			return nil, "player_equips_unavailable"
		end

		local inventory = profile:FindFirstChild("Inventory")
		local items = inventory and inventory:FindFirstChild("Items")

		if not items then
			return nil, "inventory_items_unavailable"
		end

		return {
			Modules = resolved,
			Player = player,
			Profile = profile,
			Equips = equips,
			Items = items,
			PlayerLevel = tonumber(profile:FindFirstChild("Level") and profile.Level.Value) or 1,
		}
	end

	local function getValue(item, name, fallback)
		local value = item and item:FindFirstChild(name)
		return tonumber(value and value.Value) or fallback
	end

	local function getEquippedItem(slot)
		return slot and (slot:FindFirstChildOfClass("Folder") or slot:GetChildren()[1]) or nil
	end

	local function getStats(context, item, maximum)
		local source = item
		local clone = nil

		if maximum then
			local cloned, clonedItem = pcall(item.Clone, item)

			if not cloned or not clonedItem then
				return nil, "item_clone_failed"
			end

			clone = clonedItem
			source = clone
			local limit = getValue(item, "UpgradeLimit", 0)
			local upgrade = source:FindFirstChild("Upgrade")

			if not upgrade and limit > 0 then
				upgrade = Instance.new("IntValue")
				upgrade.Name = "Upgrade"
				upgrade.Parent = source
			end

			if upgrade then
				upgrade.Value = math.max(limit, getValue(item, "Upgrade", 0))
			end
		end

		local ok, stats =
			pcall(context.Modules.Combat.GetItemStats, context.Modules.Combat, source, context.PlayerLevel)

		if clone then
			clone:Destroy()
		end

		if not ok or type(stats) ~= "table" then
			return nil, "item_stats_unavailable:" .. tostring(stats)
		end

		return stats
	end

	local function canEquip(context, item, slot)
		if item.Parent == slot then
			return true
		end

		local ok, result =
			pcall(context.Modules.Inventory.CanEquipItem, context.Modules.Inventory, context.Profile, item, slot)

		return ok and result == true
	end

	local function describeItem(context, item, slotName)
		if typeof(item) ~= "Instance" or not item.Parent then
			return nil, "item_unavailable"
		end

		if not SLOT_STAT[slotName] and slotName ~= "Offhand" then
			return nil, "unsupported_slot:" .. tostring(slotName)
		end

		local currentStats, currentError = getStats(context, item, false)
		local maximumStats, maximumError = getStats(context, item, true)

		if not currentStats or not maximumStats then
			return nil, currentError or maximumError
		end

		local tierOk, tier = pcall(context.Modules.Inventory.GetItemTier, context.Modules.Inventory, item)
		local upgrade = getValue(item, "Upgrade", 0)
		local upgradeLimit = getValue(item, "UpgradeLimit", 0)
		local statName = SLOT_STAT[slotName] or (tonumber(maximumStats.Attack) ~= nil and "Attack" or "Defense")
		local currentScore = tonumber(currentStats[statName]) or 0
		local maximumScore = tonumber(maximumStats[statName]) or currentScore

		return {
			Item = item,
			Name = item.Name,
			Slot = slotName,
			Stat = statName,
			CurrentScore = currentScore,
			MaximumScore = maximumScore,
			Upgrade = upgrade,
			UpgradeLimit = upgradeLimit,
			IsMaxUpgraded = upgradeLimit <= 0 or upgrade >= upgradeLimit,
			Tier = tierOk and (tonumber(tier) or 1) or 1,
			Level = getValue(item, "Level", 1),
			Empower = getValue(item, "Empower", 0),
			IsEquipped = item.Parent and item.Parent.Name == slotName,
		}
	end

	local function isBetter(a, b)
		if not b then
			return true
		elseif a.MaximumScore ~= b.MaximumScore then
			return a.MaximumScore > b.MaximumScore
		elseif a.CurrentScore ~= b.CurrentScore then
			return a.CurrentScore > b.CurrentScore
		elseif a.Tier ~= b.Tier then
			return a.Tier > b.Tier
		elseif a.Level ~= b.Level then
			return a.Level > b.Level
		elseif a.UpgradeLimit ~= b.UpgradeLimit then
			return a.UpgradeLimit > b.UpgradeLimit
		end

		return a.Name < b.Name
	end

	function Gear.GetSlotNames()
		return table.clone(SLOT_ORDER)
	end

	function Gear.GetBestForSlot(slotName, excludedItems)
		local context, contextError = getContext()

		if not context then
			return nil, nil, contextError
		end

		local slot = context.Equips:FindFirstChild(slotName)

		if not slot then
			return nil, nil, "equipment_slot_unavailable:" .. tostring(slotName)
		end

		local currentItem = getEquippedItem(slot)
		local current = currentItem and describeItem(context, currentItem, slotName) or nil
		local best = current

		for _, item in ipairs(context.Items:GetChildren()) do
			if not (excludedItems and excludedItems[item]) and canEquip(context, item, slot) then
				local descriptor = describeItem(context, item, slotName)

				if descriptor and isBetter(descriptor, best) then
					best = descriptor
				end
			end
		end

		return best, current
	end

	function Gear.GetBestLoadout()
		local result = {}
		local used = {}

		for _, slotName in ipairs(SLOT_ORDER) do
			local best, current, slotError = Gear.GetBestForSlot(slotName, used)

			result[slotName] = {
				Best = best,
				Current = current,
				Error = slotError,
			}

			if best and (slotName == "Primary" or slotName == "Offhand") then
				used[best.Item] = true
			end
		end

		return result
	end

	function Gear.GetProtectedItems()
		local protected = {}

		for _, slot in pairs(Gear.GetBestLoadout()) do
			local best = type(slot) == "table" and slot.Best
			local current = type(slot) == "table" and slot.Current

			if best and typeof(best.Item) == "Instance" then
				protected[best.Item] = true
			end

			if current and typeof(current.Item) == "Instance" then
				protected[current.Item] = true
			end
		end

		return protected
	end

	function Gear.GetUpgradeInfo(item)
		local context, contextError = getContext()

		if not context then
			return nil, contextError
		elseif typeof(item) ~= "Instance" or not item.Parent then
			return nil, "item_unavailable"
		end

		local upgrade = context.Modules.ItemUpgrade
		local level = getValue(item, "Upgrade", 0)
		local limit = getValue(item, "UpgradeLimit", 0)
		local costOk, cost = pcall(upgrade.GetUpgradeCostForItem, upgrade, item)
		local chanceOk, chance = pcall(upgrade.GetUpgradeChance, upgrade, item)

		return {
			Level = level,
			Limit = limit,
			IsMaxed = limit <= 0 or level >= limit,
			GoldCost = costOk and (tonumber(cost) or 0) or 0,
			Chance = chanceOk and (tonumber(chance) or 0) or 0,
			CrystalCost = math.max(0, limit - level) * 20,
		}
	end

	function Gear.GetBalances()
		local context, contextError = getContext()

		if not context then
			return nil, contextError
		end

		local goldOk, gold = pcall(context.Modules.Profile.GetGold, context.Modules.Profile, context.Profile)
		local crystalsModule = resolve("Shared.Crystals", "Crystals")
		local crystalOk, crystals = false, nil

		if crystalsModule and type(crystalsModule.GetCrystals) == "function" then
			crystalOk, crystals = pcall(crystalsModule.GetCrystals, crystalsModule, context.Player)
		end

		return {
			Gold = goldOk and (tonumber(gold) or 0) or 0,
			Crystals = crystalOk and (tonumber(crystals) or 0) or 0,
		}
	end

	function Gear.RequestUpgrade(item, useCrystals)
		local context, contextError = getContext()

		if not context then
			return false, contextError
		elseif typeof(item) ~= "Instance" or not item.Parent then
			return false, "item_unavailable"
		end

		local info, infoError = Gear.GetUpgradeInfo(item)

		if not info then
			return false, infoError
		elseif info.IsMaxed then
			return false, "item_already_maxed"
		end

		local ok, requestError = pcall(
			context.Modules.ItemUpgrade.UpgradeItem,
			context.Modules.ItemUpgrade,
			context.Player,
			item,
			useCrystals == true
		)

		if not ok then
			return false, "upgrade_request_failed:" .. tostring(requestError)
		end

		return true
	end

	function Gear.Equip(item, slotName)
		local context, contextError = getContext()

		if not context then
			return false, contextError
		end

		local slot = context.Equips:FindFirstChild(slotName)

		if not slot then
			return false, "equipment_slot_unavailable:" .. tostring(slotName)
		elseif typeof(item) ~= "Instance" or item.Parent ~= context.Items then
			return false, "item_not_in_inventory"
		elseif not canEquip(context, item, slot) then
			return false, "item_not_compatible"
		end

		local ok, equipError = pcall(context.Modules.Inventory.EquipItemClient, context.Modules.Inventory, item, slot)

		if not ok then
			return false, "equip_request_failed:" .. tostring(equipError)
		end

		local deadline = os.clock() + 2

		repeat
			if item.Parent == slot then
				return true
			end

			task.wait(0.05)
		until os.clock() >= deadline or not item.Parent

		return false, "equip_not_confirmed"
	end

	function Gear.Describe()
		local context, contextError = getContext()

		return {
			Available = context ~= nil,
			Error = contextError,
			SupportsPotentialScoring = context ~= nil,
			SupportsUpgrade = context and type(context.Modules.ItemUpgrade.UpgradeItem) == "function" or false,
			SupportsEquip = context and type(context.Modules.Inventory.EquipItemClient) == "function" or false,
		}
	end

	return Gear
end
