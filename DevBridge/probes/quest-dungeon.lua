local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime or context

assert(runtime, "World Zero runtime is not active")

local currentWorldOrder, worldError = runtime.TeleportAPI.GetCurrentWorldOrder()
local quest, questError = runtime.QuestsAPI.GetCurrent(currentWorldOrder)
local currentMission, missionError = runtime.MissionsAPI.GetCurrent()

print("current_world_order", currentWorldOrder, worldError)
print("current_mission", currentMission, missionError)
print("quest", quest)

if not quest then
	return {
		QuestError = questError,
		CurrentWorldOrder = currentWorldOrder,
	}
end

print("quest_id", quest.ID)
print("quest_name", quest.Name)
print("quest_category", quest.Category)
print("objective_type", quest.ObjectiveType)
print("objective_arguments", quest.Arguments)
print("is_dungeon", quest.IsDungeonObjective)
print("dungeon_id", quest.DungeonID)
print("dungeon_difficulty", quest.DungeonDifficulty)
print("linked_world", quest.LinkedWorld)

local selectedMission = nil
local selectionError = nil

if quest.IsDungeonObjective and not quest.DungeonID then
	selectedMission, selectionError =
		runtime.MissionsAPI.FindEasiestForWorld(
			quest.LinkedWorld or currentWorldOrder,
			quest.DungeonDifficulty or 1
		)
	print("world_dungeon_selection", selectedMission, selectionError)
end

return {
	QuestID = quest.ID,
	ObjectiveType = quest.ObjectiveType,
	Arguments = quest.Arguments,
	IsDungeonObjective = quest.IsDungeonObjective,
	DungeonID = quest.DungeonID,
	DungeonDifficulty = quest.DungeonDifficulty,
	LinkedWorld = quest.LinkedWorld,
	SelectedMissionID = selectedMission and selectedMission.ID or nil,
	SelectionError = selectionError,
	CurrentMission = currentMission ~= nil,
}
