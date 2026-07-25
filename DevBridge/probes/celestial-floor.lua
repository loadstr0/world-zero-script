local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local character = player and player.Character
local root = character
	and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
local missionObjects = workspace:FindFirstChild("MissionObjects")
local arena = missionObjects and missionObjects:FindFirstChild("Arena")
local floorValue = ReplicatedStorage:FindFirstChild("ReplicateTowerFloor")
local objective = ReplicatedStorage:FindFirstChild("ObjectiveMessage")

local function vector(value)
	return {
		X = math.round(value.X * 100) / 100,
		Y = math.round(value.Y * 100) / 100,
		Z = math.round(value.Z * 100) / 100,
	}
end

print("phase", {
	Floor = floorValue and floorValue.Value or nil,
	Objective = objective and objective.Value or nil,
	Position = root and vector(root.Position) or nil,
})

local rooms = {}

for _, room in ipairs(arena and arena:GetChildren() or {}) do
	local entry = {
		Name = room.Name,
		Class = room.ClassName,
		Children = {},
	}

	for _, child in ipairs(room:GetChildren()) do
		local childEntry = {
			Name = child.Name,
			Class = child.ClassName,
			Descendants = #child:GetDescendants(),
			Attributes = child:GetAttributes(),
			Tags = CollectionService:GetTags(child),
		}

		if child:IsA("BasePart") then
			childEntry.Position = vector(child.Position)
			childEntry.Size = vector(child.Size)
			childEntry.CanTouch = child.CanTouch
			childEntry.CanCollide = child.CanCollide
			childEntry.Transparency = child.Transparency
		end

		table.insert(entry.Children, childEntry)
	end

	table.insert(rooms, entry)
end

print("rooms", rooms)

local parts = {}

for _, instance in ipairs(workspace:GetDescendants()) do
	if instance:IsA("BasePart") and root then
		local distance = (instance.Position - root.Position).Magnitude

		if
			distance <= 450
			and (
				instance.CanTouch
				or instance.Transparency >= 0.9
				or #CollectionService:GetTags(instance) > 0
			)
		then
			table.insert(parts, {
				Path = instance:GetFullName(),
				Position = vector(instance.Position),
				Size = vector(instance.Size),
				Distance = math.round(distance * 10) / 10,
				CanTouch = instance.CanTouch,
				CanCollide = instance.CanCollide,
				Transparency = instance.Transparency,
				Tags = CollectionService:GetTags(instance),
				Attributes = instance:GetAttributes(),
			})
		end
	end
end

table.sort(parts, function(a, b)
	return a.Distance < b.Distance
end)

while #parts > 250 do
	table.remove(parts)
end

print("nearby_parts", parts)

local relevantModules = {}

for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
	if instance:IsA("LuaSourceContainer") then
		local lowerPath = string.lower(instance:GetFullName())

		if
			string.find(lowerPath, "tower", 1, true)
			or string.find(lowerPath, "celestial", 1, true)
			or string.find(lowerPath, "mission39", 1, true)
		then
			table.insert(relevantModules, {
				Path = instance:GetFullName(),
				Class = instance.ClassName,
			})
		end
	end
end

print("tower_scripts", relevantModules)

return {
	Floor = floorValue and floorValue.Value or nil,
	Objective = objective and objective.Value or nil,
	RoomCount = #rooms,
	NearbyPartCount = #parts,
	ScriptCount = #relevantModules,
}
