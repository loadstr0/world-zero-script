local Players = game:GetService("Players")
local player = Players.LocalPlayer
local character = player and player.Character
local root = character
	and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
local container = workspace:FindFirstChild("Mobs")
local entries = {}

for _, mob in ipairs(container and container:GetChildren() or {}) do
	local part = mob:IsA("Model")
		and (
			mob.PrimaryPart
				or mob:FindFirstChild("HumanoidRootPart")
				or mob:FindFirstChildWhichIsA("BasePart", true)
		)
		or nil
	local humanoid = mob:FindFirstChildWhichIsA("Humanoid", true)
	local descendants = {}

	for _, descendant in ipairs(mob:GetDescendants()) do
		table.insert(descendants, {
			Name = descendant.Name,
			Class = descendant.ClassName,
			Value = descendant:IsA("ValueBase") and tostring(descendant.Value) or nil,
			Position = descendant:IsA("BasePart") and tostring(descendant.Position) or nil,
		})
	end

	table.insert(entries, {
		Name = mob.Name,
		Class = mob.ClassName,
		Position = part and tostring(part.Position) or nil,
		Distance = part and root and (part.Position - root.Position).Magnitude or nil,
		Health = humanoid and humanoid.Health or nil,
		Attributes = mob:GetAttributes(),
		Children = #mob:GetChildren(),
		Descendants = descendants,
	})
end

print("raw_mobs", entries)
return entries
