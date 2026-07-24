return function(ctx)
	local Main = {}
	local activeRuntime = nil

	local FEATURE_ORDER = {
		"Home",
		"Farming",
		"Missions",
		"Loot",
		"Combat",
		"Teleports",
		"Player",
		"Settings",
	}

	function Main.Start()
		if activeRuntime then
			Main.Stop()
		end

		local Logger = ctx:Require("Logger")
		local config = ctx:Require("Config").Resolve()
		local valid, reason = ctx:Require("Config").Validate(config)

		if not valid then
			error("Invalid configuration: " .. tostring(reason))
		end

		local janitor = ctx:Require("Janitor").new()
		local state = ctx:Require("State").new()
		local ui = ctx:Require("RayfieldUI").new(config)

		local runtime = {
			Context = ctx,
			Config = config,
			Logger = Logger,
			Executor = ctx:Require("Executor"),
			Janitor = janitor,
			State = state,
			Game = ctx:Require("GameContext"),
			Actions = ctx:Require("Actions"),
			Navigation = ctx:Require("Navigation"),
			UI = ui,
			Stopped = false,
		}

		function runtime.Stop()
			Main.Stop()
		end

		activeRuntime = runtime
		ctx.ActiveRuntime = runtime

		for _, moduleName in ipairs(FEATURE_ORDER) do
			local feature = ctx:Require(moduleName)
			local ok, registerError = pcall(feature.Register, runtime)

			if not ok then
				Logger.error("Feature registration failed:", moduleName, registerError)
			end
		end

		ui:LoadConfiguration()
		ui:Notify("World Zero", "Modular interface loaded.", 4, "circle-check")
		Logger.info("Started in PlaceId", game.PlaceId)

		return runtime
	end

	function Main.Stop()
		local runtime = activeRuntime

		if not runtime or runtime.Stopped then
			return
		end

		runtime.Stopped = true
		runtime.Janitor:Cleanup()
		pcall(function()
			runtime.UI:Destroy()
		end)

		if ctx.ActiveRuntime == runtime then
			ctx.ActiveRuntime = nil
		end

		activeRuntime = nil
	end

	return Main
end
