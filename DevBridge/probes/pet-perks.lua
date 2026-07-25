local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function valueText(value)
	if typeof(value) == "Instance" then
		return value:GetFullName()
	end

	if type(value) == "table" then
		local keys = {}

		for key in pairs(value) do
			table.insert(keys, tostring(key))
		end

		table.sort(keys)
		return "table{" .. table.concat(keys, ",") .. "}"
	end

	return tostring(value)
end

print("=== PET AND PERK MODULES ===")

for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
	local lowered = string.lower(instance.Name)

	if (instance:IsA("ModuleScript") or instance:IsA("LocalScript"))
		and (
			string.find(lowered, "pet", 1, true)
			or string.find(lowered, "perk", 1, true)
			or string.find(lowered, "companion", 1, true)
		)
	then
		print(instance.ClassName, instance:GetFullName())

		if instance:IsA("ModuleScript") then
			local ok, module = pcall(require, instance)
			print("  require", ok, valueText(module))
		end
	end
end

print("=== EQUIPPED PET PROFILE ===")

local profileModule = require(ReplicatedStorage.Shared.Profile)
local petsModule = require(ReplicatedStorage.Shared.Pets)
local petSkillsModule = require(ReplicatedStorage.Shared.PetSkills)
local itemsModule = require(ReplicatedStorage.Shared.Items)
local equips = profileModule:GetPlayerEquips(player)
local petSlot = equips and equips:FindFirstChild("Pet")
local equippedPet = petSlot and petSlot:GetChildren()[1]

if equippedPet then
	local definition = itemsModule[equippedPet.Name]
	local skillName = petsModule:GetPetSkillFromPetRef(equippedPet)
	print(
		"equipped",
		equippedPet.Name,
		"type",
		type(definition) == "table" and definition.Type or "unknown",
		"skill",
		tostring(skillName)
	)

	for _, instance in ipairs(equippedPet:GetDescendants()) do
		if instance:IsA("ValueBase") then
			print(instance:GetFullName(), instance.ClassName, valueText(instance.Value))
		end
	end

	local skill = petSkillsModule:GetCurrentActiveSkill(player)
	print("active skill data", valueText(skill))
else
	print("no equipped pet item")
end

print("=== LIVE PET MODELS ===")

local workspacePets = workspace:FindFirstChild("Pets")

if workspacePets then
	for _, pet in ipairs(workspacePets:GetChildren()) do
		print("PET", pet:GetFullName(), "owner", tostring(pet:GetAttribute("Owner")), "target", tostring(pet:GetAttribute("Target")))

		for _, instance in ipairs(pet:GetDescendants()) do
			if instance:IsA("ValueBase") then
				print(" ", instance:GetFullName(), instance.ClassName, valueText(instance.Value))
			end
		end
	end
else
	print("workspace.Pets not found")
end

print("=== LOADED PET/PERK MODULES ===")

if type(getloadedmodules) == "function" then
	for _, moduleScript in ipairs(getloadedmodules()) do
		local lowered = string.lower(moduleScript.Name)

		if string.find(lowered, "pet", 1, true)
			or string.find(lowered, "perk", 1, true)
			or string.find(lowered, "companion", 1, true)
		then
			print(moduleScript:GetFullName())
		end
	end
end

return {
	placeId = game.PlaceId,
	player = player and player.Name or nil,
	petsFolder = workspacePets and #workspacePets:GetChildren() or 0,
}
