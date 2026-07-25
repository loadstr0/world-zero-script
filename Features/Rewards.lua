return function()
	local Rewards = {
		Id = "Rewards",
	}

	function Rewards.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Rewards)
		local claimRunning = false

		runtime.State:Set("Rewards.AutoClaimStarterPass", true)

		local function claim(showNotification)
			if claimRunning or runtime.Stopped then
				return
			end

			claimRunning = true

			task.spawn(function()
				local claims, claimError =
					runtime.StarterPassAPI.ClaimAvailable(100)

				claimRunning = false

				if claims then
					runtime.Logger.info(
						"Claimed",
						#claims,
						"Starter Pass reward(s)."
					)

					if showNotification then
						runtime.UI:Notify(
							"Starter Pass",
							"Claimed "
								.. tostring(#claims)
								.. " available reward(s).",
							5,
							0
						)
					end
				elseif
					showNotification
					and claimError ~= "no_starterpass_rewards_available"
					and claimError ~= "starterpass_inactive"
				then
					runtime.UI:Notify(
						"Starter Pass",
						"Could not claim rewards: " .. tostring(claimError),
						6,
						0
					)
				elseif showNotification then
					runtime.UI:Notify(
						"Starter Pass",
						"No earned rewards are waiting.",
						4,
						0
					)
				end
			end)
		end

		runtime.UI:CreateSection(tab, "Starter Pass")
		runtime.Controls.StarterPassAutoClaim = runtime.UI:CreateToggle(
			tab,
			"StarterPassAutoClaim",
			{
				Name = "Claim earned Starter Pass rewards automatically",
				CurrentValue = true,
				Callback = function(value)
					runtime.State:Set("Rewards.AutoClaimStarterPass", value)

					if value then
						claim(false)
					end
				end,
			}
		)

		runtime.UI:CreateButton(tab, {
			Name = "Claim available Starter Pass rewards now",
			Callback = function()
				claim(true)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show Starter Pass status",
			Callback = function()
				local state, stateError =
					runtime.StarterPassAPI.GetState()

				if not state then
					runtime.UI:Notify(
						"Starter Pass",
						"Status unavailable: " .. tostring(stateError),
						5,
						0
					)
					return
				end

				runtime.UI:Notify(
					"Starter Pass",
					"Active: "
						.. tostring(state.Active)
						.. "\nEarned rank: "
						.. tostring(state.EarnedRank)
						.. "\nFree track claimed through: "
						.. tostring(state.FreeTrack)
						.. "\nPremium track claimed through: "
						.. tostring(state.PaidTrack)
						.. "\nPremium active: "
						.. tostring(state.HasPremium),
					7,
					0
				)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Automatic rewards",
			"Only already-earned free rewards and owned premium-track rewards are claimed. The automation never purchases ranks or premium access."
		)

		local availableConnection, availableError =
			runtime.StarterPassAPI.ObserveAvailable(function()
				if runtime.State:Get("Rewards.AutoClaimStarterPass", true) then
					claim(false)
				end
			end)

		if availableConnection then
			runtime.Janitor:Add(availableConnection)
		elseif availableError then
			runtime.Logger.warn(
				"Starter Pass reward observer unavailable:",
				availableError
			)
		end

		task.defer(function()
			task.wait(2)

			if
				not runtime.Stopped
				and runtime.State:Get("Rewards.AutoClaimStarterPass", true)
			then
				claim(false)
			end
		end)
	end

	return Rewards
end
