return function()
	local Player = {
		Id = "Player",
	}

	function Player.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Player)
		local quickItemName = ""
		local localPlayer = runtime.Game.GetLocalPlayer()

		runtime.State:Set("Player.AntiIdle", true)

		if localPlayer then
			local idleConnection = localPlayer.Idled:Connect(function()
				if runtime.Stopped or not runtime.State:Get("Player.AntiIdle", true) then
					return
				end

				pcall(function()
					local virtualUser = runtime.Context.Services.VirtualUser
					local camera = workspace.CurrentCamera
					virtualUser:CaptureController()
					virtualUser:Button2Down(Vector2.zero, camera and camera.CFrame or CFrame.new())
					task.wait(0.05)
					virtualUser:Button2Up(Vector2.zero, camera and camera.CFrame or CFrame.new())
				end)
			end)
			runtime.Janitor:Add(idleConnection)
		end

		runtime.UI:CreateSection(tab, "Session")
		runtime.UI:CreateToggle(tab, "PlayerAntiIdle", {
			Name = "Prevent idle disconnects",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Player.AntiIdle", value)
			end,
		})

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
