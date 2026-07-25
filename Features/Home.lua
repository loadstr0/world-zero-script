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
			actions.Available and ("Client.Actions is available.\nInitialized: " .. tostring(actions.Initialized))
				or ("Client.Actions is unavailable.\n" .. tostring(actions.Error))
		)

		local function setControl(name, value)
			local control = runtime.Controls[name]
			local setter = control and control.Set

			if type(setter) == "function" then
				local ok = pcall(setter, control, value)

				if ok then
					return true
				end
			end

			return false
		end

		runtime.UI:CreateSection(tab, "Quick start")
		runtime.UI:CreateButton(tab, {
			Name = "Start complete safe farming",
			Callback = function()
				setControl("FarmingEnabled", true)
				setControl("QuestsEnabled", true)
				setControl("LootDropsEnabled", true)
				setControl("LootChestsEnabled", true)
				setControl("GearEnabled", true)
				runtime.UI:Notify(
					"Full farming",
					"Farming, main quests, post-kill loot, chests, and smart gear are enabled. Automatic selling and upgrade spending remain separately armed.",
					7,
					0
				)
			end,
		})
		runtime.UI:CreateButton(tab, {
			Name = "Stop all farming automation",
			Callback = function()
				setControl("FarmingEnabled", false)
				setControl("QuestsEnabled", false)
				setControl("LootDropsEnabled", false)
				setControl("LootChestsEnabled", false)
				setControl("GearEnabled", false)
				runtime.UI:Notify("Full farming", "All farming supervisors were stopped.", 4, 0)
			end,
		})
		runtime.UI:CreateParagraph(
			tab,
			"Safe preset",
			"The quick start coordinates the non-destructive farming stack. Gold/crystal upgrades and inventory selling are never armed by this button."
		)

		runtime.UI:CreateSection(tab, "Navigation")
		runtime.UI:CreateParagraph(
			tab,
			"Where things live",
			"Automation: farming, movement, survival, and attack rotation\n"
				.. "Quests & Missions: main quests, dungeon travel, rewards, and replay\n"
				.. "Loot: drops, chests, and protected inventory cleanup\n"
				.. "Gear: maximum-potential scoring, upgrading, and equipping\n"
				.. "Combat: targeting and attacks\n"
				.. "Travel: actual hubs, worlds, events, and destinations\n"
				.. "Player: session, movement, and quick items\n"
				.. "Settings: runtime details and unload"
		)
	end

	return Home
end
