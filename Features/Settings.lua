return function()
	local Settings = {
		Id = "Settings",
	}

	function Settings.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Settings)
		local details = runtime.Game.Describe()
		local capabilities = runtime.Executor.Report()
		local capabilityLines = {}
		local saving = runtime.Config.ConfigurationSaving or {}
		local updateConfig = runtime.Config.Updates or {}
		local updateLoopRunning = false

		for name, available in pairs(capabilities) do
			table.insert(capabilityLines, name .. ": " .. (available and "yes" or "no"))
		end

		table.sort(capabilityLines)

		runtime.State:Set("Updates.AutoReload", updateConfig.AutoReload == true)
		runtime.State:Set("Updates.PollInterval", tonumber(updateConfig.PollInterval) or 120)

		runtime.UI:CreateSection(tab, "Runtime")
		runtime.UI:CreateParagraph(
			tab,
			"Session",
			"Player: "
				.. tostring(details.PlayerName)
				.. "\nPlaceId: "
				.. tostring(details.PlaceId)
				.. "\nGameId: "
				.. tostring(details.GameId)
		)
		runtime.UI:CreateParagraph(tab, "Executor capabilities", table.concat(capabilityLines, "\n"))

		runtime.UI:CreateSection(tab, "Configuration")
		runtime.UI:CreateParagraph(
			tab,
			"Automatic saving",
			"Status: "
				.. (saving.Enabled and "enabled" or "disabled")
				.. "\nFolder: "
				.. tostring(saving.FolderName or "default")
				.. "\nFile: "
				.. tostring(saving.FileName or "default")
				.. "\nFlagged controls save automatically when changed."
		)
		runtime.UI:CreateButton(tab, {
			Name = "Reload saved configuration",
			Callback = function()
				runtime.UI:LoadConfiguration()
				runtime.UI:Notify("Configuration", "Saved control values were reloaded.", 4, "save")
			end,
		})

		runtime.UI:CreateSection(tab, "Updates")
		local updateStatus = runtime.UI:CreateParagraph(
			tab,
			"GitHub main",
			"Checking the current repository version..."
		)

		local function showUpdateStatus(result, updateError)
			if not result then
				updateStatus:Set({
					Title = "GitHub main",
					Content = "Update check failed: " .. tostring(updateError),
				})
				return
			end

			local content = "Loaded: "
				.. runtime.Updater.ShortCommit(result.LoadedCommit)
				.. "\nRemote: "
				.. runtime.Updater.ShortCommit(result.RemoteCommit)
				.. "\nStatus: "
				.. (result.UpdateAvailable and "update available" or "up to date")

			if result.Message then
				content = content .. "\nLatest: " .. tostring(result.Message)
			end

			updateStatus:Set({
				Title = "GitHub main",
				Content = content,
			})
		end

		local function checkForUpdate(notifyWhenCurrent)
			local result, updateError = runtime.Updater.Check()
			showUpdateStatus(result, updateError)

			if not result then
				return nil
			end

			if result.UpdateAvailable then
				runtime.UI:Notify(
					"World Zero update",
					"A newer GitHub commit is available.",
					6,
					"refresh-cw"
				)
			elseif notifyWhenCurrent then
				runtime.UI:Notify("World Zero update", "You are running the latest commit.", 4, "circle-check")
			end

			return result
		end

		local function startUpdateLoop()
			if updateLoopRunning then
				return
			end

			updateLoopRunning = true

			task.spawn(function()
				while not runtime.Stopped and runtime.State:Get("Updates.AutoReload", false) do
					local result = checkForUpdate(false)

					if result and result.UpdateAvailable then
						runtime.UI:Notify(
							"World Zero update",
							"Reloading the latest GitHub version...",
							5,
							"download"
						)
						runtime.Updater.Reload(result.RemoteCommit)
						return
					end

					task.wait(runtime.State:Get("Updates.PollInterval", 120))
				end

				updateLoopRunning = false
			end)
		end

		runtime.UI:CreateButton(tab, {
			Name = "Check for updates",
			Callback = function()
				task.spawn(checkForUpdate, true)
			end,
		})

		runtime.UI:CreateSlider(tab, "UpdatePollInterval", {
			Name = "Update check interval",
			Range = { 60, 600 },
			Increment = 30,
			Suffix = "s",
			CurrentValue = tonumber(updateConfig.PollInterval) or 120,
			Callback = function(value)
				runtime.State:Set("Updates.PollInterval", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "AutoReloadUpdates", {
			Name = "Auto reload when GitHub changes",
			CurrentValue = updateConfig.AutoReload == true,
			Callback = function(value)
				runtime.State:Set("Updates.AutoReload", value)

				if value then
					startUpdateLoop()
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Reload latest version now",
			Callback = function()
				runtime.UI:Notify("World Zero update", "Reloading from GitHub...", 4, "download")
				runtime.Updater.Reload()
			end,
		})

		if updateConfig.CheckOnStart ~= false then
			task.spawn(function()
				local result, updateError = runtime.Updater.Initialize()
				showUpdateStatus(result, updateError)
			end)
		end

		runtime.UI:CreateSection(tab, "Interface lifecycle")
		runtime.UI:CreateButton(tab, {
			Name = "Unload interface",
			Callback = function()
				runtime.Stop()
			end,
		})
	end

	return Settings
end
