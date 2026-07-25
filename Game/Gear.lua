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

	local WEAPON_PERK_WEIGHTS = {
		BonusAttack = 1,
		CritStack = 0.75,
		LifeDrain = 0.6,
		MobBoss = 0.65,
		EliteBoss = 0.35,
		TestTier5 = 0.35,
		UltCharge = 0.35,
		OpeningStrike = 0.35,
		BurnChance = 0.25,
		FrostChance = 0.25,
		PoisonChance = 0.25,
		Vampiric = 0.3,
		Oblivion = 1.5,
		Ferocious = 0.2,
		BonusRegen = 0.15,
		BonusWalkspeed = 0.1,
		GoldDrop = 0.15,
		PetFoodDrop = 0.1,
	}

	local ARMOR_PERK_WEIGHTS = {
		BonusRegen = 0.4,
		BonusWalkspeed = 0.2,
		Fortress = 0.75,
		MasterThief = 0.15,
		PoisonThorns = 0.2,
		RoughSkin = 0.2,
		Adrenaline = 0.15,
		ResistBurn = 0.12,
		ResistFrost = 0.12,
		ResistKnockdown = 0.18,
		ResistPoison = 0.12,
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

		local items, itemsError = resolve("Shared.Items", "Items")

		if not items then
			return nil, itemsError
		end

		local gearPerks, gearPerksError = resolve("Shared.Gear.GearPerks", "GearPerks")

		if not gearPerks then
			return nil, gearPerksError
		end

		return {
			Inventory = inventory,
			ItemUpgrade = upgrade,
			Combat = combat,
			Profile = profile,
			Items = items,
			GearPerks = gearPerks,
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

	local function getPerks(context, item)
		local perks = {}

		for _, value in ipairs(item:GetChildren()) do
			if value:IsA("StringValue") and string.match(value.Name, "^Perk%d+$") then
				local perkValue = value:FindFirstChild("PerkValue")
				local name = value.Value
				local definition = context.Modules.GearPerks[name]

				table.insert(perks, {
					Name = name,
					DisplayName = type(definition) == "table" and definition.DisplayName or name,
					DisplayDesc = type(definition) == "table" and definition.DisplayDesc or nil,
					Value = tonumber(perkValue and perkValue.Value) or 0,
				})
			end
		end

		table.sort(perks, function(a, b)
			return a.Name < b.Name
		end)

		return perks
	end

	local function getPerkMultiplier(slotName, perks)
		local multiplier = 1

		for _, perk in ipairs(perks) do
			local value = tonumber(perk.Value) or 0

			if slotName == "Armor" then
				if perk.Name == "BonusHP" then
					multiplier *= 1 + math.max(0, value)
				elseif perk.Name == "DodgeChance" or perk.Name == "DamageReduction" then
					multiplier *= 1 / math.max(0.05, 1 - math.clamp(value, 0, 0.95))
				elseif perk.Name == "Glass" then
					multiplier *= 0.85
				else
					multiplier *= 1 + math.max(0, value) * (ARMOR_PERK_WEIGHTS[perk.Name] or 0)
				end
			else
				multiplier *= 1 + math.max(0, value) * (WEAPON_PERK_WEIGHTS[perk.Name] or 0)
			end
		end

		return multiplier
	end

	local function getSelectionScore(descriptor, maximum)
		if not descriptor then
			return 0
		elseif maximum == false then
			return tonumber(descriptor.EffectiveCurrentScore)
				or tonumber(descriptor.CurrentScore)
				or 0
		end

		return tonumber(descriptor.EffectiveMaximumScore)
			or tonumber(descriptor.MaximumScore)
			or 0
	end

	local function getTradeEligibility(context, item)
		local definition = context.Modules.Items[item.Name]
		local upgrade = getValue(item, "Upgrade", 0)
		local upgradeLimit = item:FindFirstChild("UpgradeLimit")
		local structurallyEligible = type(definition) == "table"
			and definition.Untradeable ~= true
			and upgrade <= 0
			and not item:FindFirstChild("Exploited")
			and (not upgradeLimit or tonumber(upgradeLimit.Value) ~= 0)
		local currentlyTradable = false

		if structurallyEligible and type(context.Modules.Inventory.IsTradable) == "function" then
			local ok, result = pcall(
				context.Modules.Inventory.IsTradable,
				context.Modules.Inventory,
				item,
				context.Player
			)
			currentlyTradable = ok and result == true
		end

		-- Locked or favorited items fail the live IsTradable check, but remain valid
		-- reserves because removing that protection later restores their tradeability.
		return structurallyEligible, currentlyTradable
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
		local perks = getPerks(context, item)
		local perkMultiplier = getPerkMultiplier(slotName, perks)
		local tradeEligible, currentlyTradable = getTradeEligibility(context, item)

		return {
			Item = item,
			Name = item.Name,
			Slot = slotName,
			Stat = statName,
			CurrentScore = currentScore,
			MaximumScore = maximumScore,
			EffectiveCurrentScore = currentScore * perkMultiplier,
			EffectiveMaximumScore = maximumScore * perkMultiplier,
			PerkMultiplier = perkMultiplier,
			Perks = perks,
			Upgrade = upgrade,
			UpgradeLimit = upgradeLimit,
			IsMaxUpgraded = upgradeLimit <= 0 or upgrade >= upgradeLimit,
			Tier = tierOk and (tonumber(tier) or 1) or 1,
			Level = getValue(item, "Level", 1),
			Empower = getValue(item, "Empower", 0),
			IsEquipped = item.Parent and item.Parent.Name == slotName,
			TradeEligible = tradeEligible,
			IsTradable = currentlyTradable,
		}
	end

	local function isBetter(a, b)
		if not b then
			return true
		elseif getSelectionScore(a) ~= getSelectionScore(b) then
			return getSelectionScore(a) > getSelectionScore(b)
		elseif getSelectionScore(a, false) ~= getSelectionScore(b, false) then
			return getSelectionScore(a, false) > getSelectionScore(b, false)
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

	function Gear.GetBestForSlot(slotName, excludedItems, options)
		options = options or {}
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
		local candidates = {}

		if current and not (excludedItems and excludedItems[current.Item]) then
			table.insert(candidates, current)
		end

		for _, item in ipairs(context.Items:GetChildren()) do
			if not (excludedItems and excludedItems[item]) and canEquip(context, item, slot) then
				local descriptor = describeItem(context, item, slotName)

				if descriptor then
					table.insert(candidates, descriptor)
				end
			end
		end

		local reserved = nil

		if options.ReserveBestTradable == true then
			for _, descriptor in ipairs(candidates) do
				if descriptor.TradeEligible and isBetter(descriptor, reserved) then
					reserved = descriptor
				end
			end
		end

		local best = nil

		for _, descriptor in ipairs(candidates) do
			if
				not reserved
				or descriptor.Item ~= reserved.Item
			then
				if isBetter(descriptor, best) then
					best = descriptor
				end
			end
		end

		-- Never leave an otherwise empty slot unusable. Equipping does not bind gear;
		-- the upgrade guard below still prevents the sole reserved item from being modified.
		best = best or current or reserved

		return best, current, nil, reserved
	end

	function Gear.GetBestLoadout(options)
		options = options or {}
		local result = {}
		local used = {}

		for _, slotName in ipairs(SLOT_ORDER) do
			local best, current, slotError, reserved =
				Gear.GetBestForSlot(slotName, used, options)

			result[slotName] = {
				Best = best,
				Current = current,
				Reserved = reserved,
				Error = slotError,
			}

			if best and (slotName == "Primary" or slotName == "Offhand") then
				used[best.Item] = true
			end
		end

		return result
	end

	function Gear.GetProtectedItems(options)
		local protected = {}

		for _, slot in pairs(Gear.GetBestLoadout(options)) do
			local best = type(slot) == "table" and slot.Best
			local current = type(slot) == "table" and slot.Current
			local reserved = type(slot) == "table" and slot.Reserved

			if best and typeof(best.Item) == "Instance" then
				protected[best.Item] = true
			end

			if current and typeof(current.Item) == "Instance" then
				protected[current.Item] = true
			end

			if reserved and typeof(reserved.Item) == "Instance" then
				protected[reserved.Item] = true
			end
		end

		return protected
	end

	function Gear.IsTradeReserve(item)
		if typeof(item) ~= "Instance" then
			return false
		end

		for _, slot in pairs(Gear.GetBestLoadout({
			ReserveBestTradable = true,
		})) do
			if slot.Reserved and slot.Reserved.Item == item then
				return true, slot.Reserved
			end
		end

		return false
	end

	function Gear.ListDominatedItems(options)
		options = options or {}
		local context, contextError = getContext()

		if not context then
			return nil, contextError
		end

		local groups = {}
		local keepPerCategory = math.max(1, tonumber(options.KeepPerCategory) or 2)
		local excludedItems = options.ExcludeItems or {}

		local function addItem(item, equippedSlot)
			if typeof(item) ~= "Instance" then
				return
			end

			local definition = context.Modules.Items[item.Name]
			local itemType = definition and definition.Type
			local category = nil
			local slotName = nil

			if itemType == "Weapon" and type(definition.SubType) == "string" then
				category = "Weapon:" .. definition.SubType
				slotName = "Primary"
			elseif itemType == "Armor" then
				category = "Armor"
				slotName = "Armor"
			else
				return
			end

			local descriptor = describeItem(context, item, slotName)

			if not descriptor then
				return
			end

			descriptor.Category = category
			descriptor.IsEquipped = equippedSlot ~= nil or descriptor.IsEquipped
			descriptor.EquippedSlot = equippedSlot
			descriptor.IsExcluded = excludedItems[item] == true
			groups[category] = groups[category] or {}
			table.insert(groups[category], descriptor)
		end

		for _, slotName in ipairs(SLOT_ORDER) do
			local slot = context.Equips:FindFirstChild(slotName)
			local equipped = getEquippedItem(slot)

			if equipped then
				addItem(equipped, slotName)
			end
		end

		for _, item in ipairs(context.Items:GetChildren()) do
			addItem(item)
		end

		local result = {}

		for category, descriptors in pairs(groups) do
			table.sort(descriptors, function(a, b)
				return isBetter(a, b)
			end)

			local best = descriptors[1]

			for index, descriptor in ipairs(descriptors) do
				if
					index > keepPerCategory
					and not descriptor.IsEquipped
					and not descriptor.IsExcluded
					and descriptor.Item.Parent == context.Items
					and best
					and (
						getSelectionScore(best) > getSelectionScore(descriptor)
						or (
							getSelectionScore(best) == getSelectionScore(descriptor)
							and getSelectionScore(best, false) >= getSelectionScore(descriptor, false)
						)
					)
				then
					descriptor.DominatedBy = best.Name
					descriptor.DominatedByScore = getSelectionScore(best)
					descriptor.Category = category
					table.insert(result, descriptor)
				end
			end
		end

		table.sort(result, function(a, b)
			if getSelectionScore(a) ~= getSelectionScore(b) then
				return getSelectionScore(a) < getSelectionScore(b)
			elseif getSelectionScore(a, false) ~= getSelectionScore(b, false) then
				return getSelectionScore(a, false) < getSelectionScore(b, false)
			elseif a.Tier ~= b.Tier then
				return a.Tier < b.Tier
			elseif a.Level ~= b.Level then
				return a.Level < b.Level
			end

			return a.Name < b.Name
		end)

		return result
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

	function Gear.RequestUpgrade(item, useCrystals, options)
		local context, contextError = getContext()

		if not context then
			return false, contextError
		elseif typeof(item) ~= "Instance" or not item.Parent then
			return false, "item_unavailable"
		end

		if options and options.ReserveBestTradable == true and Gear.IsTradeReserve(item) then
			return false, "trade_reserve_protected"
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

	function Gear.Equip(item, slotName, options)
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

		if options and options.ReserveBestTradable == true and Gear.IsTradeReserve(item) then
			return false, "trade_reserve_protected"
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
			SupportsDominatedGearCleanup = context ~= nil,
			SupportsUpgrade = context and type(context.Modules.ItemUpgrade.UpgradeItem) == "function" or false,
			SupportsEquip = context and type(context.Modules.Inventory.EquipItemClient) == "function" or false,
			SupportsTradeReserve = context ~= nil,
		}
	end

	return Gear
end
