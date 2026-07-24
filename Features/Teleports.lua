return function()
	local Teleports = {
		Id = "Teleports",
	}

	function Teleports.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Travel)
		local status = runtime.TeleportAPI.Describe()
		local worlds, worldsError = runtime.TeleportAPI.ListWorlds()
		local labels = {}
		local worldByLabel = {}
		local selectedWorldId = nil

		for _, world in ipairs(worlds or {}) do
			table.insert(labels, world.Label)
			worldByLabel[world.Label] = world
		end

		if worlds and worlds[1] then
			selectedWorldId = worlds[1].ID
		end

		runtime.UI:CreateSection(tab, "World travel")
		runtime.UI:CreateParagraph(
			tab,
			"Verified destinations",
			status.Available
					and (
						tostring(status.WorldCount)
						.. " currently active destination(s) loaded from Shared.Teleport.WorldData. The game validates unlocks, level requirements, event windows, and party compatibility."
					)
				or ("Shared.Teleport unavailable: " .. tostring(status.Error))
		)

		if #labels > 0 then
			runtime.UI:CreateDropdown(tab, "WorldDestination", {
				Name = "Destination",
				Options = labels,
				CurrentOption = { labels[1] },
				MultipleOptions = false,
				Callback = function(options)
					local selected =
						options and worldByLabel[options[1]]

					if selected then
						selectedWorldId = selected.ID
					end
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Travel to selected world",
				Callback = function()
					local ok, travelError =
						runtime.TeleportAPI.ToWorld(selectedWorldId)

					runtime.UI:Notify(
						"World travel",
						ok
								and "Teleport request sent."
							or (
								"Request failed: "
								.. tostring(travelError)
							),
						5,
						0
					)
				end,
			})
		else
			runtime.UI:CreateParagraph(
				tab,
				"Destination list",
				"No active destinations were available: "
					.. tostring(worldsError)
			)
		end

		runtime.UI:CreateButton(tab, {
			Name = "Return to saved hub",
			Callback = function()
				local ok, travelError =
					runtime.TeleportAPI.ToHub()

				runtime.UI:Notify(
					"Hub travel",
					ok
							and "Hub request sent."
						or ("Request failed: " .. tostring(travelError)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show current world",
			Callback = function()
				local current, currentError =
					runtime.TeleportAPI.GetCurrentWorld()

				if not current then
					runtime.UI:Notify(
						"Current world",
						"Unavailable: " .. tostring(currentError),
						5,
						0
					)
					return
				end

				runtime.UI:Notify(
					"Current world",
					tostring(
						current.Name
							or current.NameTag
							or current.ID
					)
						.. "\nWorld ID: "
						.. tostring(current.ID or "unknown")
						.. "\nLevel requirement: "
						.. tostring(
							current.LevelRequirement or "unknown"
						),
					6,
					0
				)
			end,
		})
	end

	return Teleports
end
