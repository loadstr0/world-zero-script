local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local character = player and player.Character
local root = character
	and (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart)
local moduleScript = ReplicatedStorage:FindFirstChild("Client")
	and ReplicatedStorage.Client:FindFirstChild("Actions")
local okRequire, actions = pcall(require, moduleScript)

local function invoke(name, withSelf)
	if not okRequire or type(actions) ~= "table" or type(actions[name]) ~= "function" then
		return {
			Available = false,
		}
	end

	local results

	if withSelf then
		results = table.pack(pcall(actions[name], actions))
	else
		results = table.pack(pcall(actions[name]))
	end

	local values = {}

	for index = 2, results.n do
		table.insert(values, tostring(results[index]))
	end

	return {
		Available = true,
		Success = results[1],
		Values = values,
	}
end

local runtime = WZDB.runtime()
local report = {
	Position = root and tostring(root.Position) or nil,
	WrapperBusy = runtime and runtime.Actions and runtime.Actions.IsBusy() or nil,
	DotBusy = invoke("IsBusy", false),
	MethodBusy = invoke("IsBusy", true),
	Functions = {},
}

for _, name in ipairs({
	"IsBusy",
	"LockMovement",
	"UnlockMovement",
	"ResumeCharacterMovement",
	"StopCharacterMovement",
}) do
	report.Functions[name] = type(actions) == "table" and type(actions[name]) or nil
end

print("movement_lock", report)
return report
