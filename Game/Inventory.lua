return function(ctx)
	local Inventory = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local Players = ctx.Services.Players
	local cachedInventory = nil
	local cachedDrops = nil

	local function resolve(path, cache)
		if type(cache) == "table" then
			return cache
		end

		local moduleScript = GameContext.FindReplicated(path)

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "module_not_found:" .. path
		end

		local ok, module = pcall(require, moduleScript)

		if not ok or type(module) ~= "table" then
			return nil, "module_require_failed:" .. path
		end

		return module
	end

	local function getModules()
		local inventory, inventoryError = resolve("Shared.Inventory", cachedInventory)

		if not inventory then
			return nil, nil, inventoryError
		end

		cachedInventory = inventory
		local drops, dropsError = resolve("Shared.Drops", cachedDrops)

		if not drops then
			return nil, nil, dropsError
		end

		cachedDrops = drops
		return inventory, drops
	end

	local function getItemsFolder()
		local profile, profileError = Profile.Get()
		local inventory = profile and profile:FindFirstChild("Inventory")
		local items = inventory and inventory:FindFirstChild("Items")

		if not items then
			return nil, profileError or "inventory_items_unavailable"
		end

		return items
	end

	local function getInventoryContext()
		local profile, profileError = Profile.Get()
		local inventory = profile and profile:FindFirstChild("Inventory")
		local items = inventory and inventory:FindFirstChild("Items")

		if not inventory or not items then
			return nil, nil, profileError or "inventory_unavailable"
		end

		return inventory, items
	end

	local function callBoolean(module, methodName, item, fallbackName)
		local method = module and module[methodName]

		if type(method) == "function" then
			local ok, value = pcall(method, module, item)

			if ok then
				return value == true
			end
		end

		return item:FindFirstChild(fallbackName) ~= nil
	end

	local function isModified(item)
		local empower = item:FindFirstChild("Empower")
		local empowerValue = empower and tonumber(empower.Value) or 0
		local upgrade = item:FindFirstChild("Upgrade")
		local upgradeValue = upgrade and tonumber(upgrade.Value) or 0

		if empowerValue > 0 or upgradeValue > 0 then
			return true
		end

		if item:FindFirstChild("Perk1") or item:FindFirstChild("Perk2") or item:FindFirstChild("Perk3") then
			return true
		end

		return item:FindFirstChild("Dye") ~= nil
			or item:FindFirstChild("WeaponAura") ~= nil
			or item:FindFirstChild("Trait") ~= nil
			or item:FindFirstChild("GiftWrap") ~= nil
	end

	function Inventory.IsProtected(item, preserveModified)
		if typeof(item) ~= "Instance" or not item.Parent then
			return true, "item_unavailable"
		end

		local inventoryModule = getModules()

		if not inventoryModule then
			return true, "inventory_module_unavailable"
		end

		if callBoolean(inventoryModule, "ItemIsLocked", item, "Locked") then
			return true, "locked"
		end

		if callBoolean(inventoryModule, "ItemIsFavorited", item, "Favorited") then
			return true, "favorited"
		end

		if preserveModified ~= false and isModified(item) then
			return true, "modified"
		end

		return false
	end

	function Inventory.GetDescriptor(item)
		local inventoryModule, dropsModule, moduleError = getModules()

		if not inventoryModule or not dropsModule then
			return nil, moduleError
		end

		local tierOk, tier = pcall(inventoryModule.GetItemTier, inventoryModule, item)
		local priceOk, price = pcall(dropsModule.GetSellPrice, dropsModule, item)
		local levelValue = item:FindFirstChild("Level")
		local level = levelValue and tonumber(levelValue.Value) or 1

		if not tierOk or not priceOk then
			return nil, "item_metadata_unavailable"
		end

		return {
			Item = item,
			Name = item.Name,
			Tier = tonumber(tier) or 1,
			Level = level or 1,
			Price = tonumber(price) or 0,
		}
	end

	function Inventory.ListSellCandidates(options)
		options = options or {}
		local items, itemsError = getItemsFolder()

		if not items then
			return nil, itemsError
		end

		local maxTier = tonumber(options.MaxTier) or 1
		local maxLevel = tonumber(options.MaxLevel) or 10
		local result = {}

		for _, item in ipairs(items:GetChildren()) do
			local protected = options.ExcludeItems and options.ExcludeItems[item] == true
				or Inventory.IsProtected(item, options.PreserveModified ~= false)

			if not protected then
				local descriptor = Inventory.GetDescriptor(item)

				if
					descriptor
					and descriptor.Price > 0
					and descriptor.Tier <= maxTier
					and descriptor.Level <= maxLevel
				then
					table.insert(result, descriptor)
				end
			end
		end

		table.sort(result, function(a, b)
			if a.Tier ~= b.Tier then
				return a.Tier < b.Tier
			end

			if a.Level ~= b.Level then
				return a.Level < b.Level
			end

			return a.Name < b.Name
		end)

		return result
	end

	function Inventory.GetCapacity()
		local inventoryModule, _, moduleError = getModules()
		local inventory, items, inventoryError = getInventoryContext()

		if not inventoryModule or not inventory or not items then
			return nil, moduleError or inventoryError
		end

		local slots = inventory:FindFirstChild("Slots")
		local capacity = tonumber(slots and slots.Value)

		if not capacity then
			return nil, "inventory_slots_unavailable"
		end

		local remainingOk, remaining =
			pcall(inventoryModule.GetRemainingSpace, inventoryModule, inventory)

		if not remainingOk or tonumber(remaining) == nil then
			return nil, "inventory_remaining_space_unavailable:" .. tostring(remaining)
		end

		remaining = math.max(0, tonumber(remaining) or 0)

		return {
			Capacity = capacity,
			Used = math.max(0, capacity - remaining),
			Remaining = remaining,
			ItemCount = #items:GetChildren(),
		}
	end

	function Inventory.Sell(descriptors, preserveModified, excludeItems)
		if type(descriptors) ~= "table" or #descriptors == 0 then
			return nil, "no_items_selected"
		end

		local _, dropsModule, moduleError = getModules()

		if not dropsModule then
			return nil, moduleError
		end

		if type(dropsModule.SellItems) ~= "function" then
			return nil, "drops_missing_sellitems"
		end

		local itemsFolder, itemsError = getItemsFolder()

		if not itemsFolder then
			return nil, itemsError
		end

		local safe = {}

		for _, descriptor in ipairs(descriptors) do
			local item = descriptor and descriptor.Item

			if
				typeof(item) == "Instance"
				and item.Parent == itemsFolder
				and not (excludeItems and excludeItems[item])
			then
				local protected = Inventory.IsProtected(item, preserveModified)
				local current = Inventory.GetDescriptor(item)

				if
					not protected
					and current
					and current.Price > 0
					and current.Tier <= (tonumber(descriptor.Tier) or 0)
					and current.Level <= (tonumber(descriptor.Level) or 0)
				then
					table.insert(safe, item)
				end
			end
		end

		if #safe == 0 then
			return nil, "no_safe_items_selected"
		end

		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local ok, gold = pcall(dropsModule.SellItems, dropsModule, player, safe)

		if not ok then
			return nil, "sell_request_failed:" .. tostring(gold)
		end

		return tonumber(gold) or 0, #safe
	end

	function Inventory.Describe()
		local inventoryModule, dropsModule, moduleError = getModules()
		local items = getItemsFolder()
		local capacity = Inventory.GetCapacity()

		return {
			Available = inventoryModule ~= nil and dropsModule ~= nil,
			Error = moduleError,
			ItemCount = items and #items:GetChildren() or 0,
			Capacity = capacity and capacity.Capacity or nil,
			Remaining = capacity and capacity.Remaining or nil,
			ProtectsLocked = true,
			ProtectsFavorited = true,
			ProtectsModified = true,
		}
	end

	return Inventory
end
