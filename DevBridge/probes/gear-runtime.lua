local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.State, "World Zero runtime is not fully initialized")

local engine = runtime.Context:Require("GearEngine")
local scan = engine.Scan(runtime)

print("gear_api", runtime.GearAPI.Describe())
print("gear_enabled", runtime.State:Get("Gear.Enabled", false))
print("gear_auto_upgrade", runtime.State:Get("Gear.AutoUpgrade", false))
print("gear_auto_equip", runtime.State:Get("Gear.AutoEquip", true))
print("gear_equip_only_maxed", runtime.State:Get("Gear.EquipOnlyMaxed", false))
print("gear_minimum_improvement", runtime.State:Get("Gear.MinimumImprovement", 0))
print("gear_engine_status", engine.GetStatus(runtime))
print("inventory_capacity", runtime.InventoryAPI.GetCapacity())

local result = {}

for _, slotName in ipairs(runtime.GearAPI.GetSlotNames()) do
	local slot = scan[slotName] or {}
	local best = slot.Best
	local current = slot.Current
	local bestUpgrade = best and runtime.GearAPI.GetUpgradeInfo(best.Item) or nil
	local entry = {
		Slot = slotName,
		Error = slot.Error,
		Improvement = slot.Improvement,
		Best = best and {
			Name = best.Name,
			Path = best.Item:GetFullName(),
			CurrentScore = best.CurrentScore,
			MaximumScore = best.MaximumScore,
			Upgrade = best.Upgrade,
			UpgradeLimit = best.UpgradeLimit,
			IsMaxUpgraded = best.IsMaxUpgraded,
			Tier = best.Tier,
			Level = best.Level,
		} or nil,
		Current = current and {
			Name = current.Name,
			Path = current.Item:GetFullName(),
			CurrentScore = current.CurrentScore,
			MaximumScore = current.MaximumScore,
			Upgrade = current.Upgrade,
			UpgradeLimit = current.UpgradeLimit,
			IsMaxUpgraded = current.IsMaxUpgraded,
			Tier = current.Tier,
			Level = current.Level,
		} or nil,
		BestUpgrade = bestUpgrade,
		WouldEquip = best ~= nil
			and (not current or best.Item ~= current.Item)
			and runtime.State:Get("Gear.AutoEquip", true)
			and (
				not runtime.State:Get("Gear.EquipOnlyMaxed", false)
				or not bestUpgrade
				or bestUpgrade.IsMaxed
			),
	}

	table.insert(result, entry)
	print("gear_slot", entry)
end

return result
