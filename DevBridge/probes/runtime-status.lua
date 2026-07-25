local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

print("place", game.PlaceId)
print("game", game.GameId)
print("player", game:GetService("Players").LocalPlayer)
print("world_zero_context", env.WorldZeroContext ~= nil)
print("loader_context", context ~= nil)
print("active_runtime", runtime ~= nil)

if runtime then
	print("stopped", runtime.Stopped)
	print("active_class", runtime.ActiveClass)
	print("farming_enabled", runtime.State:Get("Farming.Enabled", false))
	print("quests_enabled", runtime.State:Get("Quests.Enabled", false))
	print("gear_enabled", runtime.State:Get("Gear.Enabled", false))
	print("navigator", runtime.Navigator.GetState())
	print("automation", runtime.FarmingEngine.GetStatus(runtime))
	print("dungeon", runtime.DungeonsAPI and runtime.DungeonsAPI.Describe() or nil)
	print("teleport_resume", runtime.TeleportResume)
end

return {
	PlaceId = game.PlaceId,
	RuntimeAvailable = runtime ~= nil,
}
