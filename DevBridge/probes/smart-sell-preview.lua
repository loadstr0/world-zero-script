local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.InventoryAPI and runtime.GearAPI, "World Zero runtime is not fully initialized")

local profileAPI = runtime.Context:Require("Profile")
local profile = profileAPI.Get()
local inventory = profile and profile:FindFirstChild("Inventory")
local inventoryItems = inventory and inventory:FindFirstChild("Items")
local items = WZDB.require("ReplicatedStorage.Shared.Items")
local combat = WZDB.require("ReplicatedStorage.Shared.Combat")
local sharedProfile = WZDB.require("ReplicatedStorage.Shared.Profile")
local player = game:GetService("Players").LocalPlayer
local equips = sharedProfile:GetPlayerEquips(player)
local playerLevel = tonumber(profile and profile:FindFirstChild("Level") and profile.Level.Value) or 1
local keepPerCategory = 2
local groups = {}

local function getValue(item, name, fallback)
	local value = item and item:FindFirstChild(name)
	return tonumber(value and value.Value) or fallback
end

local function getScore(item, statName, maximum)
	local source = item

	if maximum then
		source = item:Clone()
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

	local stats = combat:GetItemStats(source, playerLevel)

	if source ~= item then
		source:Destroy()
	end

	return tonumber(stats and stats[statName]) or 0
end

local function add(item, equipped)
	local definition = item and items[item.Name]
	local category = nil
	local statName = nil

	if definition and definition.Type == "Weapon" and type(definition.SubType) == "string" then
		category = "Weapon:" .. definition.SubType
		statName = "Attack"
	elseif definition and definition.Type == "Armor" then
		category = "Armor"
		statName = "Defense"
	else
		return
	end

	groups[category] = groups[category] or {}
	table.insert(groups[category], {
		Item = item,
		Name = item.Name,
		Category = category,
		CurrentScore = getScore(item, statName, false),
		MaximumScore = getScore(item, statName, true),
		Tier = select(1, runtime.InventoryAPI.GetDescriptor(item)).Tier,
		Level = getValue(item, "Level", 1),
		Equipped = equipped == true,
	})
end

for _, slotName in ipairs({ "Primary", "Offhand", "Armor" }) do
	local slot = equips and equips:FindFirstChild(slotName)
	local item = slot and (slot:FindFirstChildOfClass("Folder") or slot:GetChildren()[1])

	if item then
		add(item, true)
	end
end

for _, item in ipairs(inventoryItems and inventoryItems:GetChildren() or {}) do
	add(item, false)
end

local candidates = {}

for category, descriptors in pairs(groups) do
	table.sort(descriptors, function(a, b)
		if a.MaximumScore ~= b.MaximumScore then
			return a.MaximumScore > b.MaximumScore
		elseif a.CurrentScore ~= b.CurrentScore then
			return a.CurrentScore > b.CurrentScore
		elseif a.Tier ~= b.Tier then
			return a.Tier > b.Tier
		elseif a.Level ~= b.Level then
			return a.Level > b.Level
		end

		return a.Name < b.Name
	end)

	local best = descriptors[1]

	for index, descriptor in ipairs(descriptors) do
		local protected, reason = runtime.InventoryAPI.IsProtected(descriptor.Item, true)
		local inventoryDescriptor = runtime.InventoryAPI.GetDescriptor(descriptor.Item)

		if
			index > keepPerCategory
			and not descriptor.Equipped
			and not protected
			and inventoryDescriptor
			and inventoryDescriptor.Price > 0
		then
			descriptor.Price = inventoryDescriptor.Price
			descriptor.DominatedBy = best and best.Name or nil
			table.insert(candidates, descriptor)
		elseif index > keepPerCategory and not descriptor.Equipped then
			print("smart_sell_protected", descriptor.Name, reason or "unsellable")
		end
	end

	print("smart_sell_category", category, descriptors)
end

table.sort(candidates, function(a, b)
	return a.MaximumScore < b.MaximumScore
end)

print("smart_sell_preview", {
	Capacity = runtime.InventoryAPI.GetCapacity(),
	KeepPerCategory = keepPerCategory,
	Candidates = candidates,
})

return candidates
