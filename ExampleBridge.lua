-- World Zero Script/ExampleBridge.lua
--
-- Replace both URLs after publishing the folder to a raw-file host.

getgenv().WorldZeroBase = "https://raw.githubusercontent.com/loadstr0/world-zero-script/main/"

getgenv().WorldZeroBridge = {
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
		FileName = "WorldZeroV1",
	},

	Debug = true,
}

local loaderUrl = getgenv().WorldZeroBase
	.. "Loader.lua?cache="
	.. tostring(os.time())
	.. tostring(math.random(1000, 9999))

local source = game:HttpGet(loaderUrl)
local loader, compileError = loadstring(source)

if not loader then
	error("[WorldZeroBridge] Loader compilation failed: " .. tostring(compileError), 0)
end

loader()
