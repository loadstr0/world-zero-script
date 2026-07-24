-- Single-file public entry point.
-- Replace YOUR_NAME/YOUR_REPO before publishing, or set WorldZeroBase first.

local env = getgenv()
local defaultBase = "https://raw.githubusercontent.com/YOUR_NAME/YOUR_REPO/main/"
local base = env.WorldZeroBase or defaultBase

if string.find(base, "YOUR_NAME/YOUR_REPO", 1, true) then
	error("[WorldZero] Configure the GitHub owner and repository in Bootstrap.lua.", 0)
end

if string.sub(base, -1) ~= "/" then
	base = base .. "/"
end

env.WorldZeroBase = base
env.WorldZeroBridge = env.WorldZeroBridge or {
	Window = {
		Name = "World Zero",
		LoadingTitle = "World Zero",
		LoadingSubtitle = "Modular Rayfield build",
		Theme = "Default",
		ToggleUIKeybind = "K",
	},
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "WorldZero",
		FileName = "WorldZeroConfig",
	},
	Debug = true,
}

loadstring(game:HttpGet(base .. "Loader.lua"))()

