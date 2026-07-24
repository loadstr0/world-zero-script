return function(ctx)
	local Config = {}

	local DEFAULTS = {
		Debug = true,
		RayfieldUrl = "https://sirius.menu/rayfield",
		FlagPrefix = "WZ_",
		Window = {
			Name = "World Zero",
			Icon = 0,
			LoadingTitle = "World Zero",
			LoadingSubtitle = "Modular Rayfield build",
			ShowText = "World Zero",
			Theme = "Default",
			ToggleUIKeybind = "K",
			DisableRayfieldPrompts = false,
			DisableBuildWarnings = false,
		},
		ConfigurationSaving = {
			Enabled = true,
			FolderName = "WorldZero",
			FileName = "WorldZeroConfig",
		},
	}

	local function copy(value)
		if type(value) ~= "table" then
			return value
		end

		local result = {}

		for key, child in pairs(value) do
			result[key] = copy(child)
		end

		return result
	end

	local function merge(target, source)
		if type(source) ~= "table" then
			return target
		end

		for key, value in pairs(source) do
			if type(value) == "table" and type(target[key]) == "table" then
				merge(target[key], value)
			else
				target[key] = copy(value)
			end
		end

		return target
	end

	function Config.Resolve()
		return merge(copy(DEFAULTS), ctx.Bridge or {})
	end

	function Config.Validate(config)
		if type(config.RayfieldUrl) ~= "string" or config.RayfieldUrl == "" then
			return false, "missing_rayfield_url"
		end

		if type(config.Window) ~= "table" or type(config.Window.Name) ~= "string" then
			return false, "invalid_window_config"
		end

		return true
	end

	return Config
end

