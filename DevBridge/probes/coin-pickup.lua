local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local player = Players.LocalPlayer
local character = player and player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local runtime = WZDB.runtime()

local function describe(instance)
	local position = nil

	if instance:IsA("BasePart") then
		position = instance.Position
	elseif instance:IsA("Model") then
		position = instance:GetPivot().Position
	end

	return {
		Name = instance.Name,
		ClassName = instance.ClassName,
		Path = instance:GetFullName(),
		Parent = instance.Parent and instance.Parent:GetFullName() or nil,
		Position = position and tostring(position) or nil,
		PlayerDistance = position and root and (position - root.Position).Magnitude or nil,
		Attributes = instance:GetAttributes(),
	}
end

local report = {
	Player = player and player.Name or nil,
	RootPosition = root and tostring(root.Position) or nil,
	Runtime = runtime ~= nil,
	State = {},
	Coins = {},
	Pets = {},
	DropsModule = {},
}

if runtime and runtime.State then
	for _, key in ipairs({
		"Loot.DropsEnabled",
		"Loot.CollectionRange",
		"Loot.CollectDuringCombat",
		"Loot.AfterKillSweep",
		"Farming.Enabled",
		"Quest.Enabled",
	}) do
		report.State[key] = runtime.State:Get(key)
	end

	if runtime.DropsAPI then
		local ok, result, reason = pcall(runtime.DropsAPI.List, math.huge)
		report.DropsAPI = {
			Ok = ok,
			Count = ok and type(result) == "table" and #result or nil,
			Reason = reason,
		}
	end
end

local coins = workspace:FindFirstChild("Coins")
if coins then
	report.CoinChildren = #coins:GetChildren()
	report.CoinDescendants = #coins:GetDescendants()
	for _, instance in ipairs(coins:GetDescendants()) do
		if instance:IsA("BasePart") or instance:IsA("Model") then
			table.insert(report.Coins, describe(instance))
		end
	end
end

for _, containerName in ipairs({ "Pets", "Characters", "Live" }) do
	local container = workspace:FindFirstChild(containerName)
	if container then
		for _, instance in ipairs(container:GetChildren()) do
			local owner = instance:GetAttribute("Owner")
				or instance:GetAttribute("Player")
				or instance:GetAttribute("PlayerName")
				or instance:GetAttribute("UserId")
			if owner == player or owner == player.Name or tostring(owner) == tostring(player.UserId) then
				table.insert(report.Pets, describe(instance))
			elseif string.find(string.lower(instance.Name), string.lower(player.Name), 1, true) then
				table.insert(report.Pets, describe(instance))
			end
		end
	end
end

local dropsModule = ReplicatedStorage:FindFirstChild("Shared")
	and ReplicatedStorage.Shared:FindFirstChild("Drops")
if dropsModule then
	report.DropsModule.Path = dropsModule:GetFullName()
	local ok, exports = pcall(require, dropsModule)
	report.DropsModule.RequireOk = ok
	if ok and type(exports) == "table" then
		local keys = {}
		for key, value in pairs(exports) do
			table.insert(keys, tostring(key) .. ":" .. typeof(value))
		end
		table.sort(keys)
		report.DropsModule.Exports = keys
	end

	for _, child in ipairs(dropsModule:GetChildren()) do
		table.insert(report.DropsModule, describe(child))
	end
end

WZDB.log("coin-pickup", report)
return report
