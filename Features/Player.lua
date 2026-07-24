return function()
	local Player = {
		Id = "Player",
		Title = "Player",
		Icon = "user",
	}

	function Player.Register(runtime)
		local tab = runtime.UI:CreateTab(Player.Id, Player.Title, Player.Icon)
		local quickItemName = ""

		runtime.UI:CreateSection(tab, "Movement")
		runtime.UI:CreateToggle(tab, "PlayerSprint", {
			Name = "Sprint",
			CurrentValue = false,
			Callback = function(value)
				if value then
					runtime.Actions.Sprint()
				else
					runtime.Actions.StopSprint()
				end
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Toggle mount",
			Callback = function()
				runtime.Actions.ToggleMount(false)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Sheath / unsheath",
			Callback = function()
				runtime.Actions.Sheath()
			end,
		})

		runtime.UI:CreateSection(tab, "Quick item")
		runtime.UI:CreateInput(tab, "PlayerQuickItemName", {
			Name = "Inventory item name",
			CurrentValue = "",
			PlaceholderText = "Exact item instance name",
			RemoveTextAfterFocusLost = false,
			Callback = function(value)
				quickItemName = value
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Use quick item",
			Callback = function()
				if quickItemName == "" then
					runtime.UI:Notify("Quick item", "Enter an exact inventory item name first.", 4, "info")
					return
				end

				runtime.Actions.UseQuickItem(quickItemName)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Verified source",
			"These controls call exported Client.Actions methods. Mounting still requires one equipped mount, and quick-item names must match an inventory instance."
		)
	end

	return Player
end
