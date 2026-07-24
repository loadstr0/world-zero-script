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
		FileName = "WorldZeroConfig",
	},

	Debug = true,
}

loadstring(game:HttpGet(getgenv().WorldZeroBase .. "Loader.lua"))()
