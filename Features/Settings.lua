return function()
	local Settings = {
		Id = "Settings",
	}

	function Settings.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Settings)
		local details = runtime.Game.Describe()
		local capabilities = runtime.Executor.Report()
		local capabilityLines = {}

		for name, available in pairs(capabilities) do
			table.insert(capabilityLines, name .. ": " .. (available and "yes" or "no"))
		end

		table.sort(capabilityLines)

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
