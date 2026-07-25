local env = getgenv()
local context = env.WorldZeroRuntime or env.WorldZeroContext
local runtime = context and context.ActiveRuntime

assert(runtime and runtime.Game, "World Zero runtime is not fully initialized")

local player = game:GetService("Players").LocalPlayer
local root = runtime.Game.GetRootPart()
local missionObjects = workspace:FindFirstChild("MissionObjects")

local function vector(value)
	return value and {
		X = math.floor(value.X * 10) / 10,
		Y = math.floor(value.Y * 10) / 10,
		Z = math.floor(value.Z * 10) / 10,
	} or nil
end

local function partEntry(part)
	return part and {
		Name = part.Name,
		Path = part:GetFullName(),
		Position = vector(part.Position),
		Distance = root and math.floor((root.Position - part.Position).Magnitude * 10) / 10 or nil,
		Size = vector(part.Size),
		CanCollide = part.CanCollide,
		CanTouch = part.CanTouch,
		HasTouchInterest = part:FindFirstChildOfClass("TouchTransmitter") ~= nil,
	} or nil
end

local result = {
	Root = vector(root and root.Position),
	Children = {},
	Checkpoints = {},
	TouchTargets = {},
	RouteMarkers = {},
	VisibleObjectiveText = {},
}

for _, child in ipairs(missionObjects and missionObjects:GetChildren() or {}) do
	table.insert(result.Children, child.Name .. ":" .. child.ClassName)
end

table.sort(result.Children)

local checkpoints = missionObjects and missionObjects:FindFirstChild("Checkpoints")

for _, child in ipairs(checkpoints and checkpoints:GetChildren() or {}) do
	if child:IsA("BasePart") then
		table.insert(result.Checkpoints, partEntry(child))
	end
end

for _, instance in ipairs(missionObjects and missionObjects:GetDescendants() or {}) do
	if instance:IsA("BasePart") and instance:FindFirstChildOfClass("TouchTransmitter") then
		table.insert(result.TouchTargets, partEntry(instance))
	end
end

for _, child in ipairs(missionObjects and missionObjects:GetChildren() or {}) do
	if
		child:IsA("BasePart")
		and (
			string.find(child.Name, "Trigger")
			or string.find(child.Name, "Teleport")
			or string.find(child.Name, "TalkPart")
		)
	then
		table.insert(result.RouteMarkers, partEntry(child))
	end
end

table.sort(result.RouteMarkers, function(a, b)
	return (a.Distance or math.huge) < (b.Distance or math.huge)
end)

table.sort(result.TouchTargets, function(a, b)
	return (a.Distance or math.huge) < (b.Distance or math.huge)
end)

local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
local objectiveGui = playerGui and playerGui:FindFirstChild("MissionObjective")

local function visible(instance)
	local current = instance

	while current and current ~= playerGui do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		elseif current:IsA("LayerCollector") and not current.Enabled then
			return false
		end

		current = current.Parent
	end

	return true
end

for _, instance in ipairs(objectiveGui and objectiveGui:GetDescendants() or {}) do
	if
		(instance:IsA("TextLabel") or instance:IsA("TextButton"))
		and visible(instance)
		and string.match(instance.Text or "", "%S")
	then
		table.insert(result.VisibleObjectiveText, instance.Text)
	end
end

print("dungeon2_stage", result)
return result
