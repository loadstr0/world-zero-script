local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.State, "World Zero runtime is not fully initialized")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local currentMission, missionError = runtime.MissionsAPI.GetCurrent()

print("place", game.PlaceId)
print("current_mission", currentMission, missionError)
print("automation", runtime.FarmingEngine.GetStatus(runtime))

local function listMethods(label, module)
	local methods = {}

	for key, value in pairs(module or {}) do
		if type(value) == "function" then
			table.insert(methods, tostring(key))
		end
	end

	table.sort(methods)
	print(label, methods)
end

local shared = ReplicatedStorage:FindFirstChild("Shared")
local missionsScript = shared and shared:FindFirstChild("Missions")
local objectivesScript = shared and shared:FindFirstChild("Objectives")
local missionsModule = missionsScript and require(missionsScript) or nil
local objectivesModule = objectivesScript and require(objectivesScript) or nil

listMethods("mission_methods", missionsModule)
listMethods("objective_methods", objectivesModule)

local topLevel = {}

for _, child in ipairs(workspace:GetChildren()) do
	table.insert(topLevel, {
		Name = child.Name,
		Class = child.ClassName,
		Children = #child:GetChildren(),
		Tags = CollectionService:GetTags(child),
		Attributes = child:GetAttributes(),
	})
end

table.sort(topLevel, function(a, b)
	return a.Name < b.Name
end)
print("workspace_top_level", topLevel)

local interesting = {}
local patterns = {
	"objective",
	"mission",
	"dungeon",
	"gate",
	"door",
	"wave",
	"trigger",
	"interact",
	"portal",
	"finish",
	"defend",
	"farm",
	"crop",
	"well",
	"villager",
	"enemy",
	"mob",
	"spawn",
}

for _, instance in ipairs(workspace:GetDescendants()) do
	if #interesting >= 300 then
		break
	end

	local lowerName = string.lower(instance.Name)
	local tags = CollectionService:GetTags(instance)
	local matched = #tags > 0

	if not matched then
		for _, pattern in ipairs(patterns) do
			if string.find(lowerName, pattern, 1, true) then
				matched = true
				break
			end
		end
	end

	if matched then
		table.insert(interesting, {
			Path = instance:GetFullName(),
			Class = instance.ClassName,
			Tags = tags,
			Attributes = instance:GetAttributes(),
		})
	end
end

print("workspace_mechanics", interesting)

local player = Players.LocalPlayer
local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
local objectiveText = {}

for _, instance in ipairs(playerGui and playerGui:GetDescendants() or {}) do
	if #objectiveText >= 100 then
		break
	end

	if
		(instance:IsA("TextLabel") or instance:IsA("TextButton"))
		and instance.Visible
		and type(instance.Text) == "string"
		and instance.Text ~= ""
	then
		local lowerPath = string.lower(instance:GetFullName())

		if
			string.find(lowerPath, "objective", 1, true)
			or string.find(lowerPath, "mission", 1, true)
			or string.find(lowerPath, "dungeon", 1, true)
		then
			table.insert(objectiveText, {
				Path = instance:GetFullName(),
				Text = instance.Text,
			})
		end
	end
end

print("objective_ui", objectiveText)

return {
	PlaceId = game.PlaceId,
	CurrentMission = currentMission,
	MechanicCount = #interesting,
	ObjectiveTextCount = #objectiveText,
}
