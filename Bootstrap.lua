-- Single-file public entry point.
-- Public entry point for loadstr0/world-zero-script.

local env = getgenv()
local defaultBase = "https://raw.githubusercontent.com/loadstr0/world-zero-script/main/"
local base = env.WorldZeroBase or defaultBase

if env.WorldZeroReloading ~= true then
	env.WorldZeroLoadedCommit = nil
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
