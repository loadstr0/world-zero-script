return function()
	local Missions = {
		Id = "Missions",
	}

	function Missions.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Automation)
		local status = runtime.MissionsAPI.Describe()
		local missionList, listError = runtime.MissionsAPI.List()
		local difficulties, difficultyError =
			runtime.MissionsAPI.ListDifficulties()
		local missionLabels = {}
		local missionByLabel = {}
		local difficultyLabels = {}
		local difficultyByLabel = {}
		local selectedMissionId = nil
		local selectedDifficultyId = 1
		local finishSequence = 0

		for _, mission in ipairs(missionList or {}) do
			table.insert(missionLabels, mission.Label)
			missionByLabel[mission.Label] = mission
		end

		for _, difficulty in ipairs(difficulties or {}) do
			table.insert(difficultyLabels, difficulty.Label)
			difficultyByLabel[difficulty.Label] = difficulty
		end

		if missionList and missionList[1] then
			selectedMissionId = missionList[1].ID
		end

		runtime.State:Set("Missions.FinishAction", "Replay")
		runtime.State:Set("Missions.AutoFinishEnabled", false)
		runtime.State:Set("Missions.AutoClaimReward", true)
		runtime.State:Set("Missions.FinishDelay", 4)

		runtime.UI:CreateSection(tab, "Missions")
		runtime.UI:CreateParagraph(
			tab,
			"Verified mission integration",
			status.Available
					and (
						tostring(status.MissionCount)
						.. " production mission(s) loaded from Shared.Missions. Access, level, party, reward, and replay checks remain server-authoritative."
					)
				or ("Shared.Missions unavailable: " .. tostring(status.Error))
		)

		if #missionLabels == 0 then
			runtime.UI:CreateParagraph(
				tab,
				"Mission list",
				"No mission options were available: "
					.. tostring(listError)
			)
			return
		end

		runtime.UI:CreateDropdown(tab, "MissionSelection", {
			Name = "Mission",
			Options = missionLabels,
			CurrentOption = { missionLabels[1] },
			MultipleOptions = false,
			Callback = function(options)
				local selected =
					options and missionByLabel[options[1]]

				if selected then
					selectedMissionId = selected.ID
				end
			end,
		})

		runtime.UI:CreateDropdown(tab, "MissionDifficulty", {
			Name = "Difficulty",
			Options = difficultyLabels,
			CurrentOption = {
				difficultyLabels[1]
					or ("Difficulty 1 [1]"),
			},
			MultipleOptions = false,
			Callback = function(options)
				local selected =
					options and difficultyByLabel[options[1]]

				if selected then
					selectedDifficultyId = selected.ID
				end
			end,
		})

		if #difficultyLabels == 0 then
			runtime.UI:CreateParagraph(
				tab,
				"Difficulty list",
				"Difficulty metadata was unavailable: "
					.. tostring(difficultyError)
			)
		end

		runtime.UI:CreateButton(tab, {
			Name = "Start selected mission",
			Callback = function()
				local ok, startError = runtime.TeleportAPI.ToMission(
					selectedMissionId,
					selectedDifficultyId
				)

				runtime.UI:Notify(
					"Mission travel",
					ok
							and "Mission request sent."
						or ("Request failed: " .. tostring(startError)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Matchmake selected mission",
			Callback = function()
				local ok, queueError = runtime.MissionsAPI.Queue(
					selectedMissionId,
					selectedDifficultyId
				)

				runtime.UI:Notify(
					"Mission queue",
					ok
							and "Matchmaking request sent."
						or ("Queue failed: " .. tostring(queueError)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Leave matchmaking queue",
			Callback = function()
				local ok, leaveError =
					runtime.MissionsAPI.LeaveQueue()

				runtime.UI:Notify(
					"Mission queue",
					ok
							and "Leave-queue request sent."
						or ("Request failed: " .. tostring(leaveError)),
					5,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show current mission",
			Callback = function()
				local current, currentError =
					runtime.MissionsAPI.GetCurrent()

				if not current then
					runtime.UI:Notify(
						"Current mission",
						"No active mission: " .. tostring(currentError),
						5,
						0
					)
					return
				end

				runtime.UI:Notify(
					"Current mission",
					tostring(current.NameTag or current.Name or current.ID)
						.. "\nID: "
						.. tostring(current.ID)
						.. "\nLevel requirement: "
						.. tostring(current.LevelRequirement or "unknown"),
					6,
					0
				)
			end,
		})

		runtime.UI:CreateSection(tab, "Mission completion")
		runtime.UI:CreateToggle(tab, "MissionAutoFinishEnabled", {
			Name = "Enable mission completion automation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set(
					"Missions.AutoFinishEnabled",
					value
				)
			end,
		})

		runtime.UI:CreateDropdown(tab, "MissionFinishAction", {
			Name = "After a successful mission",
			Options = { "Replay", "Return to world", "Do nothing" },
			CurrentOption = { "Replay" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set(
					"Missions.FinishAction",
					options and options[1] or "Replay"
				)
			end,
		})

		runtime.UI:CreateToggle(tab, "MissionAutoClaimReward", {
			Name = "Claim free mission reward automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set(
					"Missions.AutoClaimReward",
					value
				)
			end,
		})

		runtime.UI:CreateSlider(tab, "MissionFinishDelay", {
			Name = "Completion action delay",
			Range = { 1, 20 },
			Increment = 1,
			Suffix = "s",
			CurrentValue = 4,
			Callback = function(value)
				runtime.State:Set("Missions.FinishDelay", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Reward and replay behavior",
			"The free reward uses the same GetMissionPrize request as the reward screen; inventory and eligibility are checked by the server. Replay only succeeds for the party leader. Other members are marked ready and follow the leader's choice."
		)

		local finishConnection, finishError =
			runtime.MissionsAPI.ObserveFinished(
				function(...)
					local arguments = { ... }
					local failed = arguments[3] == true

					if failed then
						return
					end

					if
						not runtime.State:Get(
							"Missions.AutoFinishEnabled",
							false
						)
					then
						return
					end

					finishSequence = finishSequence + 1
					local sequence = finishSequence

					task.spawn(function()
						if
							runtime.State:Get(
								"Missions.AutoClaimReward",
								true
							)
						then
							task.wait(1)

							if
								runtime.Stopped
								or sequence ~= finishSequence
								or not runtime.State:Get(
									"Missions.AutoFinishEnabled",
									false
								)
							then
								return
							end

							local reward, rewardError =
								runtime.MissionsAPI.ClaimFreeReward()

							if reward then
								runtime.UI:Notify(
									"Mission reward",
									tostring(reward.Count)
										.. "x "
										.. tostring(reward.Name)
										.. " claimed.",
									5,
									0
								)
							else
								runtime.UI:Notify(
									"Mission reward",
									"No free reward was claimed: "
										.. tostring(rewardError),
									5,
									0
								)
							end
						end

						task.wait(
							runtime.State:Get(
								"Missions.FinishDelay",
								4
							)
						)

						if
							runtime.Stopped
							or sequence ~= finishSequence
							or not runtime.State:Get(
								"Missions.AutoFinishEnabled",
								false
							)
						then
							return
						end

						local action =
							runtime.State:Get(
								"Missions.FinishAction",
								"Replay"
							)

						if action == "Do nothing" then
							return
						end

						local ok, actionError =
							runtime.MissionsAPI.FinishChoice(
								action == "Replay"
							)

						if not ok then
							runtime.UI:Notify(
								"Mission completion",
								"Completion action failed: "
									.. tostring(actionError),
								6,
								0
							)
						end
					end)
				end
			)

		if finishConnection then
			runtime.Janitor:Add(finishConnection)
		elseif finishError then
			runtime.UI:CreateParagraph(
				tab,
				"Completion listener",
				"Unavailable: " .. tostring(finishError)
			)
		end
	end

	return Missions
end
