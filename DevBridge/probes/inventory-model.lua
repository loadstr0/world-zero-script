local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.InventoryAPI and runtime.GearAPI, "World Zero runtime is not fully initialized")

local player = game:GetService("Players").LocalPlayer
local profileAPI = runtime.Context:Require("Profile")
local profile = profileAPI.Get()
local inventory = profile and profile:FindFirstChild("Inventory")
local items = inventory and inventory:FindFirstChild("Items")
local sharedInventory = WZDB.require("ReplicatedStorage.Shared.Inventory")
local sharedDrops = WZDB.require("ReplicatedStorage.Shared.Drops")

print("capacity", runtime.InventoryAPI.GetCapacity())

local moduleKeys = {}

for key, value in pairs(sharedInventory or {}) do
	table.insert(moduleKeys, tostring(key) .. ":" .. typeof(value))
end

table.sort(moduleKeys)
print("inventory_module_keys", moduleKeys)

local result = {}

for index, item in ipairs(items and items:GetChildren() or {}) do
	if index > 40 then
		break
	end

	local children = {}
	local attributes = {}

	for _, child in ipairs(item:GetChildren()) do
		table.insert(children, {
			Name = child.Name,
			Class = child.ClassName,
			Value = child:IsA("ValueBase") and child.Value or nil,
		})
	end

	for name, value in pairs(item:GetAttributes()) do
		attributes[name] = value
	end

	local entry = {
		Name = item.Name,
		Class = item.ClassName,
		Path = item:GetFullName(),
		Children = children,
		Attributes = attributes,
		Descriptor = runtime.InventoryAPI.GetDescriptor(item),
	}

	if sharedInventory then
		for _, methodName in ipairs({
			"GetItemType",
			"GetItemClass",
			"GetEquipmentType",
			"GetItemCategory",
			"GetItemTier",
		}) do
			local method = sharedInventory[methodName]

			if type(method) == "function" then
				local ok, value = pcall(method, sharedInventory, item)
				entry[methodName] = ok and value or ("ERROR:" .. tostring(value))
			end
		end
	end

	if sharedDrops and type(sharedDrops.GetSellPrice) == "function" then
		local ok, value = pcall(sharedDrops.GetSellPrice, sharedDrops, item)
		entry.SellPrice = ok and value or nil
	end

	table.insert(result, entry)
	print("inventory_item", entry)
end

return result
