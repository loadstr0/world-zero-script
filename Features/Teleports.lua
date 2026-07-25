return function()
	local Teleports = {
		Id = "Teleports",
	}

	function Teleports.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Travel)
		local status = runtime.TeleportAPI.Describe()
		local worlds, worldsError = runtime.TeleportAPI.ListWorlds()
		local hubs = runtime.TeleportAPI.ListHubs(true) or {}
		local events = runtime.TeleportAPI.ListEvents() or {}
		local labels = {}
		local worldByLabel = {}
		local selectedWorldId = nil
		local selectedHubId = nil
		local selectedEventId = nil

		for _, world in ipairs(worlds or {}) do
			table.insert(labels, world.Label)
			worldByLabel[world.Label] = world
		end

		if worlds and worlds[1] then
			selectedWorldId = worlds[1].ID
		end

		local function makeOptions(entries)
			local optionLabels = {}
			local entryByLabel = {}

			for _, entry in ipairs(entries) do
				local label = entry.Label .. " • " .. entry.Kind .. " • L" .. tostring(entry.LevelRequirement)
				table.insert(optionLabels, label)
				entryByLabel[label] = entry
			end

			return optionLabels, entryByLabel
		end

		local hubLabels, hubByLabel = makeOptions(hubs)
		local eventLabels, eventByLabel = makeOptions(events)

		if hubs[1] then
			selectedHubId = hubs[1].ID
		end

		if events[1] then
			selectedEventId = events[1].ID
		end

		runtime.UI:CreateSection(tab, "Actual hubs")
		runtime.UI:CreateParagraph(
			tab,
			"Hub directory",
			tostring(#hubs)
				.. " currently active town/event hub(s) are loaded directly from WorldData. These are real TeleportToHub destinations, not hardcoded place IDs."
		)

		if #hubLabels > 0 then
			runtime.UI:CreateDropdown(tab, "HubDestination", {
				Name = "Hub",
				Options = hubLabels,
				CurrentOption = { hubLabels[1] },
				MultipleOptions = false,
				Callback = function(options)
					local selected = options and hubByLabel[options[1]]

					if selected then
						selectedHubId = selected.ID
					end
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Travel to selected hub",
				Callback = function()
					local ok, travelError = runtime.TeleportAPI.ToHub(selectedHubId)

					runtime.UI:Notify(
						"Hub travel",
						ok and "Hub request sent." or ("Request failed: " .. tostring(travelError)),
						5,
						0
					)
				end,
			})
		end

		runtime.UI:CreateButton(tab, {
			Name = "Return to saved hub",
			Callback = function()
				local ok, travelError = runtime.TeleportAPI.ToHub()

				runtime.UI:Notify(
					"Hub travel",
					ok and "Saved-hub request sent." or ("Request failed: " .. tostring(travelError)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateSection(tab, "World travel")
		runtime.UI:CreateParagraph(
			tab,
			"Verified destinations",
			status.Available
					and (tostring(status.WorldCount) .. " currently active destination(s) loaded from Shared.Teleport.WorldData. The game validates unlocks, level requirements, event windows, and party compatibility.")
				or ("Shared.Teleport unavailable: " .. tostring(status.Error))
		)

		if #labels > 0 then
			runtime.UI:CreateDropdown(tab, "WorldDestination", {
				Name = "Destination",
				Options = labels,
				CurrentOption = { labels[1] },
				MultipleOptions = false,
				Callback = function(options)
					local selected = options and worldByLabel[options[1]]

					if selected then
						selectedWorldId = selected.ID
					end
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Travel to selected world",
				Callback = function()
					local ok, travelError = runtime.TeleportAPI.ToWorld(selectedWorldId)

					runtime.UI:Notify(
						"World travel",
						ok and "Teleport request sent." or ("Request failed: " .. tostring(travelError)),
						5,
						0
					)
				end,
			})
		else
			runtime.UI:CreateParagraph(
				tab,
				"Destination list",
				"No active destinations were available: " .. tostring(worldsError)
			)
		end

		runtime.UI:CreateSection(tab, "Live event destinations")
		runtime.UI:CreateParagraph(
			tab,
			"Active events",
			#events > 0
					and (tostring(#events) .. " currently active event destination(s) passed the game's start/end-time checks.")
				or "No event destination is active in WorldData right now."
		)

		if #eventLabels > 0 then
			runtime.UI:CreateDropdown(tab, "EventDestination", {
				Name = "Event destination",
				Options = eventLabels,
				CurrentOption = { eventLabels[1] },
				MultipleOptions = false,
				Callback = function(options)
					local selected = options and eventByLabel[options[1]]

					if selected then
						selectedEventId = selected.ID
					end
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Travel to selected event",
				Callback = function()
					local selected = eventByLabel[eventLabels[1]]

					for label, event in pairs(eventByLabel) do
						if event.ID == selectedEventId then
							selected = event
							break
						end
					end

					local ok, travelError

					if selected and selected.IsHub then
						ok, travelError = runtime.TeleportAPI.ToHub(selectedEventId)
					else
						ok, travelError = runtime.TeleportAPI.ToWorld(selectedEventId)
					end

					runtime.UI:Notify(
						"Event travel",
						ok and "Event request sent." or ("Request failed: " .. tostring(travelError)),
						5,
						0
					)
				end,
			})
		end

		runtime.UI:CreateButton(tab, {
			Name = "Show current world",
			Callback = function()
				local current, currentError = runtime.TeleportAPI.GetCurrentWorld()

				if not current then
					runtime.UI:Notify("Current world", "Unavailable: " .. tostring(currentError), 5, 0)
					return
				end

				runtime.UI:Notify(
					"Current world",
					tostring(current.Name or current.NameTag or current.ID)
						.. "\nWorld ID: "
						.. tostring(current.ID or "unknown")
						.. "\nLevel requirement: "
						.. tostring(current.LevelRequirement or "unknown"),
					6,
					0
				)
			end,
		})
	end

	return Teleports
end
