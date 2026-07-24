return function()
	local Home = {}

	function Home.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Home)
		local details = runtime.Game.Describe()
		local actions = runtime.Actions.Describe()

		runtime.UI:CreateSection(tab, "Overview")
		runtime.UI:CreateParagraph(
			tab,
			"World Zero",
			"Modular Rayfield interface\n"
				.. "Player: "
				.. tostring(details.PlayerName)
				.. "\nPlaceId: "
				.. tostring(details.PlaceId)
		)

		runtime.UI:CreateSection(tab, "System status")
		runtime.UI:CreateParagraph(
			tab,
			"Client integration",
			actions.Available
					and ("Client.Actions is available.\nInitialized: " .. tostring(actions.Initialized))
				or ("Client.Actions is unavailable.\n" .. tostring(actions.Error))
		)

		runtime.UI:CreateSection(tab, "Navigation")
		runtime.UI:CreateParagraph(
			tab,
			"Where things live",
			"Automation: farming, missions, and loot\n"
				.. "Combat: targeting and attacks\n"
				.. "Travel: worlds and destinations\n"
				.. "Player: movement and items\n"
				.. "Settings: runtime details and unload"
		)
	end

	return Home
end

