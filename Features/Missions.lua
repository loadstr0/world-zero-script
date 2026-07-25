return function(ctx)
	local Missions = {
		Id = "Missions",
	}

	local Engine = ctx:Require("FarmingEngine")

	function Missions.Register(runtime)
		local tab = runtime.UI:CreateNavigationTab(runtime.Navigation.Missions)
		local status = runtime.MissionsAPI.Describe()
		local questStatus = runtime.QuestsAPI.Describe()
		local missionList, listError = runtime.MissionsAPI.List()
		local difficulties, difficultyError = runtime.MissionsAPI.ListDifficulties()
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
		runtime.State:Set("Missions.AutoRetryFailed", true)
		runtime.State:Set("Missions.AutoClaimReward", true)
		runtime.State:Set("Missions.FinishDelay", 4)
		runtime.State:Set("Missions.FailedRetryDelay", 4)
		runtime.State:Set("Quests.Enabled", false)
		runtime.State:Set("Quests.AutoClaim", true)
		runtime.State:Set("Quests.RouteToArea", true)
		runtime.State:Set("Quests.AutoWorldTravel", true)
		runtime.State:Set("Quests.AutoDungeonTravel", true)
		runtime.State:Set("Quests.AutoDungeonFinish", true)
		runtime.State:Set("Quests.MapWideSearch", true)
		runtime.State:Set("Quests.SearchRange", 10000)
		runtime.State:Set("Dungeons.AutoStart", true)
		runtime.State:Set("Dungeons.AutoProgression", true)
		runtime.State:Set("Dungeons.AutoTowerProgression", true)
		runtime.State:Set("Dungeons.AutoSkipCutscenes", true)
		runtime.State:Set("Dungeons.DefensePriority", true)
		runtime.State:Set("Dungeons.HoldDefense", true)

		runtime.UI:CreateSection(tab, "Tracked quests")
		runtime.Controls.QuestsEnabled = runtime.UI:CreateToggle(tab, "QuestAutomationEnabled", {
			Name = "Enable tracked quest automation",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Quests.Enabled", value)
				Engine.Reconcile(runtime)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestAutoClaim", {
			Name = "Claim completed quests automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.AutoClaim", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestRouteToArea", {
			Name = "Travel to quest objective areas",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.RouteToArea", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestAutoWorldTravel", {
			Name = "Travel to the quest's world automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.AutoWorldTravel", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestAutoDungeonTravel", {
			Name = "Start required main-quest dungeons",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.AutoDungeonTravel", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestAutoDungeonFinish", {
			Name = "Claim and leave completed quest dungeons",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.AutoDungeonFinish", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "QuestMapWideSearch", {
			Name = "Search the entire loaded map for quest mobs",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Quests.MapWideSearch", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "QuestMobSearchRange", {
			Name = "Fallback quest mob search range",
			Range = { 500, 100000 },
			Increment = 500,
			Suffix = " studs",
			CurrentValue = 10000,
			Callback = function(value)
				runtime.State:Set("Quests.SearchRange", value)
			end,
		})

		runtime.UI:CreateParagraph(
			tab,
			"Quest routing",
			questStatus.Available
					and "Main/world-story quests are always selected before side, daily, weekly, guild, or event quests. KillMob objectives scan the entire loaded map by default. DoDungeon and DoDungeonWithDifficulty objectives start their exact mission and difficulty, queue Bootstrap, then resume combat after teleport."
				or ("Shared.Quests unavailable: " .. tostring(questStatus.Error))
		)

		runtime.UI:CreateButton(tab, {
			Name = "Show tracked quest",
			Callback = function()
				local currentWorldOrder = runtime.TeleportAPI.GetCurrentWorldOrder()
				local quest, questError = runtime.QuestsAPI.GetCurrent(currentWorldOrder)

				if not quest then
					runtime.UI:Notify("Tracked quest", "No active quest: " .. tostring(questError), 5, 0)
					return
				end

				runtime.UI:Notify(
					"Tracked quest",
					quest.Name
						.. "\nID: "
						.. tostring(quest.ID)
						.. "\nObjective: "
						.. quest.ObjectiveType
						.. "\nCategory: "
						.. tostring(quest.Category)
						.. " | explicitly tracked: "
						.. tostring(quest.IsTracked)
						.. "\nProgress: "
						.. tostring(quest.Progress)
						.. "/"
						.. tostring(quest.Required)
						.. "\nReady to claim: "
						.. tostring(quest.ReadyToClaim)
						.. "\nRoute available: "
						.. tostring(quest.Location ~= nil)
						.. "\nQuest world/current world: "
						.. tostring(quest.LinkedWorld)
						.. "/"
						.. tostring(currentWorldOrder)
						.. "\nQuest ref: "
						.. tostring(quest.Reference)
						.. "\nDungeon/difficulty: "
						.. tostring(quest.DungeonID)
						.. "/"
						.. tostring(quest.DungeonDifficulty or 1)
						.. "\nRoute error: "
						.. tostring(quest.LocationError)
						.. "\nMob names: "
						.. table.concat(quest.AllowedMobNames, ", "),
					7,
					0
				)
			end,
		})

		runtime.UI:CreateButton(tab, {
			Name = "Show quest automation diagnosis",
			Callback = function()
				local decision = Engine.GetStatus(runtime)

				if not decision then
					runtime.UI:Notify("Quest diagnosis", "Automation has not produced a decision yet.", 5, 0)
					return
				end

				local quest = decision.Quest
				local dungeon = decision.Dungeon
				local navigation = decision.Navigator or {}
				runtime.UI:Notify(
					"Quest diagnosis",
					"Quest: "
						.. tostring(quest and quest.Name or "none")
						.. "\nCategory: "
						.. tostring(quest and quest.Category or "none")
						.. "\nQuest target: "
						.. tostring(decision.QuestTarget and decision.QuestTarget.NameTag or "none")
						.. "\nFallback combat target: "
						.. tostring(decision.FarmTarget and decision.FarmTarget.NameTag or "none")
						.. "\nDungeon phase: "
						.. tostring(dungeon and dungeon.Phase or "none")
						.. " | next stage: "
						.. tostring(dungeon and dungeon.ProgressionName or "none")
						.. "\nRouting: "
						.. tostring(decision.Routing)
						.. " | error: "
						.. tostring(decision.RouteError)
						.. "\nCollecting: "
						.. tostring(decision.Collecting)
						.. " | error: "
						.. tostring(decision.CollectionError)
						.. "\nNavigation: "
						.. tostring(navigation.Status)
						.. " | owner: "
						.. tostring(navigation.Owner)
						.. "\nWaypoints: "
						.. tostring(navigation.Waypoint)
						.. "/"
						.. tostring(navigation.WaypointCount),
					9,
					0
				)
			end,
		})

		runtime.UI:CreateSection(tab, "Dungeon missions")
		runtime.UI:CreateToggle(tab, "DungeonAutoStart", {
			Name = "Enter mission-start triggers automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.AutoStart", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "DungeonAutoProgression", {
			Name = "Advance traversal and checkpoint triggers",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.AutoProgression", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "DungeonAutoTowerProgression", {
			Name = "Advance Celestial Tower floors automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.AutoTowerProgression", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "DungeonAutoSkipCutscenes", {
			Name = "Vote to skip dungeon cutscenes automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.AutoSkipCutscenes", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "DungeonDefensePriority", {
			Name = "Protect damaged defense objectives first",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.DefensePriority", value)
			end,
		})
		runtime.UI:CreateToggle(tab, "DungeonHoldDefense", {
			Name = "Hold the defense point between waves",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Dungeons.HoldDefense", value)
			end,
		})
		runtime.UI:CreateParagraph(
			tab,
			"Dungeon supervisor",
			"Mission start colliders, traversal triggers, checkpoints, wave gaps, protected objects, mob waves, mission completion, rewards, and return travel are handled as separate dungeon phases. Celestial Tower arena gates and next-floor portals are read from the live floor controller."
		)

		local cutsceneConnection, cutsceneError =
			runtime.MissionsAPI.ObserveCutscene(function()
				if not runtime.State:Get("Dungeons.AutoSkipCutscenes", true) then
					return
				end

				task.defer(function()
					local skipped, skipError = runtime.MissionsAPI.SkipCutscene()

					if not skipped then
						runtime.Logger.warn(
							"Automatic cutscene skip failed",
							skipError
						)
					end
				end)
			end)

		if cutsceneConnection then
			runtime.Janitor:Add(cutsceneConnection)
		elseif cutsceneError then
			runtime.Logger.warn(
				"Cutscene observer unavailable",
				cutsceneError
			)
		end

		task.defer(function()
			task.wait(1)

			if not runtime.Stopped then
				runtime.MissionsAPI.RepairCamera()
			end
		end)

		runtime.UI:CreateSection(tab, "Manual dungeon selection")
		runtime.UI:CreateParagraph(
			tab,
			"Verified mission integration",
			status.Available
					and (tostring(status.MissionCount) .. " production mission(s) loaded from Shared.Missions. Access, level, party, reward, and replay checks remain server-authoritative.")
				or ("Shared.Missions unavailable: " .. tostring(status.Error))
		)

		if #missionLabels == 0 then
			runtime.UI:CreateParagraph(
				tab,
				"Mission list",
				"No mission options were available: " .. tostring(listError)
			)
		else
			runtime.UI:CreateDropdown(tab, "MissionSelection", {
				Name = "Mission",
				Options = missionLabels,
				CurrentOption = { missionLabels[1] },
				MultipleOptions = false,
				Callback = function(options)
					local selected = options and missionByLabel[options[1]]

					if selected then
						selectedMissionId = selected.ID
					end
				end,
			})

			runtime.UI:CreateDropdown(tab, "MissionDifficulty", {
				Name = "Difficulty",
				Options = difficultyLabels,
				CurrentOption = {
					difficultyLabels[1] or "Difficulty 1 [1]",
				},
				MultipleOptions = false,
				Callback = function(options)
					local selected = options and difficultyByLabel[options[1]]

					if selected then
						selectedDifficultyId = selected.ID
					end
				end,
			})

			if #difficultyLabels == 0 then
				runtime.UI:CreateParagraph(
					tab,
					"Difficulty list",
					"Difficulty metadata was unavailable: " .. tostring(difficultyError)
				)
			end

			runtime.UI:CreateButton(tab, {
				Name = "Start selected mission",
				Callback = function()
					local ok, startError = runtime.TeleportAPI.ToMission(selectedMissionId, selectedDifficultyId)

					runtime.UI:Notify(
						"Mission travel",
						ok and "Mission request sent." or ("Request failed: " .. tostring(startError)),
						5,
						0
					)
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Matchmake selected mission",
				Callback = function()
					local ok, queueError = runtime.MissionsAPI.Queue(selectedMissionId, selectedDifficultyId)

					runtime.UI:Notify(
						"Mission queue",
						ok and "Matchmaking request sent." or ("Queue failed: " .. tostring(queueError)),
						5,
						0
					)
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Leave matchmaking queue",
				Callback = function()
					local ok, leaveError = runtime.MissionsAPI.LeaveQueue()

					runtime.UI:Notify(
						"Mission queue",
						ok and "Leave-queue request sent." or ("Request failed: " .. tostring(leaveError)),
						5,
						0
					)
				end,
			})

			runtime.UI:CreateButton(tab, {
				Name = "Show current mission",
				Callback = function()
					local current, currentError = runtime.MissionsAPI.GetCurrent()

					if not current then
						runtime.UI:Notify("Current mission", "No active mission: " .. tostring(currentError), 5, 0)
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
		end

		runtime.UI:CreateSection(tab, "Dungeon end screen")
		runtime.UI:CreateToggle(tab, "MissionAutoRetryFailed", {
			Name = "Retry failed missions and Towers automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Missions.AutoRetryFailed", value)
			end,
		})

		runtime.UI:CreateSlider(tab, "MissionFailedRetryDelay", {
			Name = "Failed-run retry delay",
			Range = { 1, 20 },
			Increment = 1,
			Suffix = "s",
			CurrentValue = 4,
			Callback = function(value)
				runtime.State:Set("Missions.FailedRetryDelay", value)
			end,
		})

		runtime.UI:CreateToggle(tab, "MissionAutoFinishEnabled", {
			Name = "Automate dungeon reward and exit",
			CurrentValue = false,
			Callback = function(value)
				runtime.State:Set("Missions.AutoFinishEnabled", value)
			end,
		})

		runtime.UI:CreateDropdown(tab, "MissionFinishAction", {
			Name = "After a successful mission",
			Options = { "Replay", "Return to world", "Do nothing" },
			CurrentOption = { "Replay" },
			MultipleOptions = false,
			Callback = function(options)
				runtime.State:Set("Missions.FinishAction", options and options[1] or "Replay")
			end,
		})

		runtime.UI:CreateToggle(tab, "MissionAutoClaimReward", {
			Name = "Claim free mission reward automatically",
			CurrentValue = true,
			Callback = function(value)
				runtime.State:Set("Missions.AutoClaimReward", value)
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
			"Failed-run retry is independent from successful completion automation and includes Celestial Tower deaths. The free reward uses the same GetMissionPrize request as the reward screen; inventory and eligibility are checked by the server. Replay only succeeds for the party leader. Other members are marked ready and follow the leader's choice."
		)

		local failedRetryScheduled = false

		local function scheduleFailedRetry()
			if
				failedRetryScheduled
				or not runtime.State:Get("Missions.AutoRetryFailed", true)
			then
				return false
			end

			failedRetryScheduled = true
			finishSequence = finishSequence + 1
			local sequence = finishSequence

			task.spawn(function()
				task.wait(tonumber(runtime.State:Get("Missions.FailedRetryDelay", 4)) or 4)

				if runtime.Stopped or sequence ~= finishSequence then
					failedRetryScheduled = false
					return
				end

				runtime.TeleportAPI.QueueBootstrap()
				local ok, retryError = runtime.MissionsAPI.FinishChoice(true)

				if not ok then
					failedRetryScheduled = false
					runtime.UI:Notify(
						"Mission retry",
						"Automatic retry failed: " .. tostring(retryError),
						6,
						0
					)
				end
			end)
			return true
		end

		local finishConnection, finishError = runtime.MissionsAPI.ObserveFinished(function(...)
			local arguments = { ... }
			local failed = arguments[3] == true

			if failed then
				scheduleFailedRetry()
				return
			end

			local currentWorldOrder = runtime.TeleportAPI.GetCurrentWorldOrder()
			local quest = runtime.QuestsAPI.GetCurrent(currentWorldOrder)
			local questDungeonFinish = runtime.State:Get("Quests.Enabled", false)
				and runtime.State:Get("Quests.AutoDungeonFinish", true)
				and quest
				and quest.IsDungeonObjective == true
			local missionFinish = runtime.State:Get("Missions.AutoFinishEnabled", false)

			if not missionFinish and not questDungeonFinish then
				return
			end

			finishSequence = finishSequence + 1
			local sequence = finishSequence

			task.spawn(function()
				if runtime.State:Get("Missions.AutoClaimReward", true) then
					task.wait(1)

					if runtime.Stopped or sequence ~= finishSequence then
						return
					end

					local rewards, rewardError = runtime.MissionsAPI.ClaimAvailableRewards(3)

					if rewards then
						local names = {}

						for _, reward in ipairs(rewards) do
							table.insert(names, tostring(reward.Count) .. "x " .. tostring(reward.Name))
						end

						runtime.UI:Notify(
							"Mission reward",
							table.concat(names, ", ") .. " claimed.",
							5,
							0
						)
					else
						runtime.UI:Notify(
							"Mission reward",
							"No free reward was claimed: " .. tostring(rewardError),
							5,
							0
						)
					end
				end

				task.wait(tonumber(runtime.State:Get("Missions.FinishDelay", 4)) or 4)

				if runtime.Stopped or sequence ~= finishSequence then
					return
				end

				local action = questDungeonFinish and "Return to world"
					or runtime.State:Get("Missions.FinishAction", "Replay")

				if action == "Do nothing" then
					return
				end

				runtime.TeleportAPI.QueueBootstrap()
				local ok, actionError = runtime.MissionsAPI.FinishChoice(action == "Replay")

				if not ok then
					runtime.UI:Notify("Mission completion", "Completion action failed: " .. tostring(actionError), 6, 0)
				end
			end)
		end)

		if finishConnection then
			runtime.Janitor:Add(finishConnection)
		elseif finishError then
			runtime.UI:CreateParagraph(tab, "Completion listener", "Unavailable: " .. tostring(finishError))
		end

		task.spawn(function()
			for _ = 1, 40 do
				if runtime.Stopped or workspace:GetAttribute("MissionCleared") == true then
					return
				end

				local missionState = runtime.MissionsAPI.GetRuntimeState()
				local dungeonState = runtime.DungeonsAPI.GetState()
				local failedBeforeInitialization = workspace:GetAttribute("MissionCleared") == false
					and missionState
					and missionState.Active == true
					and tonumber(missionState.Lives) == 0
					and dungeonState
					and dungeonState.Phase == "Rewards"

				if failedBeforeInitialization then
					scheduleFailedRetry()
					return
				end

				task.wait(0.5)
			end
		end)
	end

	return Missions
end
