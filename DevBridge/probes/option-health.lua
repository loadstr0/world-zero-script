local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.State, "World Zero runtime is not fully initialized")

local worldOrder = runtime.TeleportAPI.GetCurrentWorldOrder()
local quest, questError = runtime.QuestsAPI.GetCurrent(worldOrder)
local dungeon = runtime.DungeonsAPI.GetState()
local gearEngine = runtime.Context:Require("GearEngine")

local report = {
	PlaceId = game.PlaceId,
	Class = runtime.ActiveClass,
	Stopped = runtime.Stopped,
	TeleportResume = runtime.TeleportResume,
	Executor = runtime.Executor.Report(),
	Integrations = {
		Actions = runtime.Actions.Describe(),
		Missions = runtime.MissionsAPI.Describe(),
		Quests = runtime.QuestsAPI.Describe(),
		Teleports = runtime.TeleportAPI.Describe(),
		Gear = runtime.GearAPI.Describe(),
		Inventory = runtime.InventoryAPI.Describe(),
		Drops = runtime.DropsAPI.Describe(),
		Chests = runtime.ChestsAPI.Describe(),
		Navigator = runtime.Navigator.Describe(),
		Dungeon = runtime.DungeonsAPI.Describe(),
	},
	Enabled = {
		Farming = runtime.State:Get("Farming.Enabled", false),
		Quests = runtime.State:Get("Quests.Enabled", false),
		LootDrops = runtime.State:Get("Loot.DropsEnabled", false),
		LootChests = runtime.State:Get("Loot.ChestsEnabled", false),
		Gear = runtime.State:Get("Gear.Enabled", false),
		AutoSell = runtime.State:Get("Loot.AutoSellEnabled", false),
	},
	Engines = {
		Farming = runtime.FarmingEngine.GetStatus(runtime),
		Gear = gearEngine.GetStatus(runtime),
		Inventory = runtime.InventoryEngine.GetStatus(runtime),
	},
	Quest = quest,
	QuestError = questError,
	Dungeon = dungeon,
}

print("option_health", report)
return report
