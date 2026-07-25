local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local character = player and player.Character
local root = character
	and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
local humanoid = character and character:FindFirstChildOfClass("Humanoid")

local function vector(value)
	if typeof(value) == "Vector3" then
		return {
			X = math.round(value.X * 100) / 100,
			Y = math.round(value.Y * 100) / 100,
			Z = math.round(value.Z * 100) / 100,
		}
	end

	return value
end

local function safeRequire(instance)
	if not instance or not instance:IsA("ModuleScript") then
		return nil, "module_not_found"
	end

	local ok, result = pcall(require, instance)
	return ok and result or nil, ok and nil or tostring(result)
end

local function valueOf(instance)
	if instance and instance:IsA("ValueBase") then
		return instance.Value
	end

	return nil
end

local shared = ReplicatedStorage:FindFirstChild("Shared")
local missions, missionsError = safeRequire(shared and shared:FindFirstChild("Missions"))
local mobs, mobsError = safeRequire(shared and shared:FindFirstChild("Mobs"))
local towers, towersError = safeRequire(shared and shared:FindFirstChild("Towers"))
local missionData
local currentMission

if missions then
	pcall(function()
		missionData = missions:GetMissionData()
	end)
	pcall(function()
		currentMission = missions:GetCurrentMission()
	end)
end

local missionId = workspace:GetAttribute("MissionId")
	or workspace:GetAttribute("MissionID")
	or valueOf(ReplicatedStorage:FindFirstChild("MissionId"))
	or valueOf(ReplicatedStorage:FindFirstChild("MissionID"))
local selectedMission = type(missionData) == "table" and missionData[missionId] or nil

print("identity", {
	PlaceId = game.PlaceId,
	JobId = game.JobId,
	MissionId = missionId,
	WorkspaceAttributes = workspace:GetAttributes(),
	CurrentMission = currentMission,
	Mission = selectedMission,
})
print("player", {
	Character = character and character:GetFullName() or nil,
	Position = root and vector(root.Position) or nil,
	Health = humanoid and humanoid.Health or nil,
	MaxHealth = humanoid and humanoid.MaxHealth or nil,
})
print("modules", {
	Missions = missions ~= nil,
	MissionsError = missionsError,
	Mobs = mobs ~= nil,
	MobsError = mobsError,
	Towers = towers ~= nil,
	TowersError = towersError,
})

local replicatedValues = {}

for _, instance in ipairs(ReplicatedStorage:GetChildren()) do
	if instance:IsA("ValueBase") then
		table.insert(replicatedValues, {
			Name = instance.Name,
			Class = instance.ClassName,
			Value = instance.Value,
			Attributes = instance:GetAttributes(),
		})
	end
end

print("replicated_values", replicatedValues)

local missionObjects = workspace:FindFirstChild("MissionObjects")
local mechanics = {}
local mechanicPatterns = {
	"boss",
	"chest",
	"door",
	"elevator",
	"exit",
	"floor",
	"gate",
	"lobby",
	"next",
	"portal",
	"spawn",
	"start",
	"teleport",
	"trigger",
	"wave",
}

for _, instance in ipairs(missionObjects and missionObjects:GetDescendants() or workspace:GetDescendants()) do
	if #mechanics >= 400 then
		break
	end

	local lowerName = string.lower(instance.Name)
	local matched = false

	for _, pattern in ipairs(mechanicPatterns) do
		if string.find(lowerName, pattern, 1, true) then
			matched = true
			break
		end
	end

	if matched or #CollectionService:GetTags(instance) > 0 then
		local entry = {
			Path = instance:GetFullName(),
			Class = instance.ClassName,
			Attributes = instance:GetAttributes(),
			Tags = CollectionService:GetTags(instance),
		}

		if instance:IsA("BasePart") then
			entry.Position = vector(instance.Position)
			entry.Size = vector(instance.Size)
			entry.CanTouch = instance.CanTouch
			entry.CanCollide = instance.CanCollide
		elseif instance:IsA("ValueBase") then
			entry.Value = instance.Value
		end

		table.insert(mechanics, entry)
	end
end

print("mechanics", mechanics)

local mobList = {}

if mobs and type(mobs.GetAllMobs) == "function" then
	local ok, liveMobs = pcall(mobs.GetAllMobs, mobs)

	if ok and type(liveMobs) == "table" then
		for _, model in pairs(liveMobs) do
			if typeof(model) == "Instance" then
				local part = model.PrimaryPart
					or model:FindFirstChild("Collider")
					or model:FindFirstChild("HumanoidRootPart", true)
				local data

				if type(mobs.GetMobData) == "function" then
					pcall(function()
						data = mobs:GetMobData(model)
					end)
				end

				table.insert(mobList, {
					Path = model:GetFullName(),
					Position = part and vector(part.Position) or nil,
					Distance = part and root
						and math.round((part.Position - root.Position).Magnitude * 10) / 10
						or nil,
					Attributes = model:GetAttributes(),
					Tags = CollectionService:GetTags(model),
					Data = data,
				})
			end
		end
	end
end

print("mobs", mobList)

local visibleText = {}
local playerGui = player and player:FindFirstChildOfClass("PlayerGui")

for _, instance in ipairs(playerGui and playerGui:GetDescendants() or {}) do
	if #visibleText >= 150 then
		break
	end

	if
		(instance:IsA("TextLabel") or instance:IsA("TextButton"))
		and instance.Visible
		and instance.Text ~= ""
	then
		table.insert(visibleText, {
			Path = instance:GetFullName(),
			Text = instance.Text,
		})
	end
end

print("visible_ui", visibleText)

local topLevel = {}

for _, instance in ipairs(workspace:GetChildren()) do
	table.insert(topLevel, {
		Name = instance.Name,
		Class = instance.ClassName,
		Children = #instance:GetChildren(),
		Attributes = instance:GetAttributes(),
	})
end

print("workspace", topLevel)

return {
	PlaceId = game.PlaceId,
	MissionId = missionId,
	MissionName = selectedMission and selectedMission.NameTag or nil,
	MechanicCount = #mechanics,
	MobCount = #mobList,
	VisibleTextCount = #visibleText,
}
