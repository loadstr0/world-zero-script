return function(ctx)
	local Missions = {}

	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript =
			GameContext.FindReplicated("Shared.Missions")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_missions_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_missions_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	local function getPlayer()
		return Players.LocalPlayer
	end

	function Missions.List()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetMissionData) ~= "function" then
			return nil, "missions_missing_get_mission_data"
		end

		local ok, data = pcall(module.GetMissionData, module)

		if not ok or type(data) ~= "table" then
			return nil, "mission_data_unavailable"
		end

		local result = {}

		for key, mission in pairs(data) do
			if
				type(mission) == "table"
				and mission.Disabled ~= true
				and mission.ShowOnProduction ~= false
			then
				local id = tonumber(mission.ID) or tonumber(key)

				if id then
					local name =
						tostring(
							mission.NameTag
								or mission.Name
								or ("Mission " .. tostring(id))
						)

					table.insert(result, {
						ID = id,
						Name = name,
						Label = name .. " [" .. tostring(id) .. "]",
						LevelRequirement =
							tonumber(mission.LevelRequirement) or 1,
						DisplayWorldID =
							tonumber(mission.DisplayWorldID) or 999,
						WorldMissionID =
							tonumber(mission.WorldMissionID) or 999,
						Data = mission,
					})
				end
			end
		end

		table.sort(result, function(a, b)
			if a.DisplayWorldID ~= b.DisplayWorldID then
				return a.DisplayWorldID < b.DisplayWorldID
			end

			if a.WorldMissionID ~= b.WorldMissionID then
				return a.WorldMissionID < b.WorldMissionID
			end

			return a.ID < b.ID
		end)

		return result
	end

	function Missions.ListDifficulties()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		local count = 5

		if type(module.GetTotalPossibleDifficulties) == "function" then
			local countOk, countValue = pcall(
				module.GetTotalPossibleDifficulties,
				module
			)

			local numericCount = tonumber(countValue)

			if countOk and numericCount then
				count = math.max(1, numericCount)
			end
		end

		local result = {}

		for id = 1, count do
			local name = nil

			if type(module.GetNameFromDifficulty) == "function" then
				local nameOk, nameValue = pcall(
					module.GetNameFromDifficulty,
					module,
					nil,
					id
				)

				if nameOk and nameValue ~= nil then
					name = tostring(nameValue)
				end
			end

			name = name or ("Difficulty " .. tostring(id))

			table.insert(result, {
				ID = id,
				Name = name,
				Label = name .. " [" .. tostring(id) .. "]",
			})
		end

		return result
	end

	function Missions.GetCurrent()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetCurrentMissionData) ~= "function" then
			return nil, "missions_missing_current_mission"
		end

		local ok, mission =
			pcall(module.GetCurrentMissionData, module)

		if not ok then
			return nil, "current_mission_query_failed"
		end

		if not mission then
			return nil, "no_active_mission"
		end

		return mission
	end

	function Missions.Queue(missionId, difficultyId)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.RequestQueue) ~= "function" then
			return false, "missions_missing_request_queue"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local ok, queueError = pcall(
			module.RequestQueue,
			module,
			player,
			tonumber(missionId),
			tonumber(difficultyId) or 1
		)

		if not ok then
			return false, "mission_queue_failed:" .. tostring(queueError)
		end

		return true
	end

	function Missions.LeaveQueue()
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.LeaveQueue) ~= "function" then
			return false, "missions_missing_leave_queue"
		end

		local player = getPlayer()
		local ok, leaveError =
			pcall(module.LeaveQueue, module, player)

		if not ok then
			return false, "leave_queue_failed:" .. tostring(leaveError)
		end

		return true
	end

	function Missions.ClaimFreeReward()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetMissionPrize) ~= "function" then
			return nil, "missions_missing_get_prize"
		end

		local ok, reward, count =
			pcall(module.GetMissionPrize, module)

		if not ok then
			return nil, "mission_prize_request_failed"
		end

		if not reward then
			return nil, "no_free_reward_available"
		end

		return {
			Item = reward,
			Count = tonumber(count) or 1,
			Name = tostring(reward.Name),
		}
	end

	function Missions.FinishChoice(replay)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		if
			type(module.SetLeaveChoice) ~= "function"
			or type(module.NotifyReadyToLeave) ~= "function"
		then
			return false, "missions_missing_finish_choice"
		end

		local choiceOk, choiceError = pcall(
			module.SetLeaveChoice,
			module,
			player,
			replay == true
		)

		if not choiceOk then
			return false, "leave_choice_failed:" .. tostring(choiceError)
		end

		local readyOk, readyError = pcall(
			module.NotifyReadyToLeave,
			module,
			player,
			false
		)

		if not readyOk then
			return false, "ready_to_leave_failed:" .. tostring(readyError)
		end

		return true
	end

	function Missions.ObserveFinished(callback)
		local moduleScript =
			GameContext.FindReplicated("Shared.Missions")
		local event = moduleScript
			and moduleScript:FindFirstChild("MissionFinished")

		if not event or not event:IsA("RemoteEvent") then
			return nil, "mission_finished_event_not_found"
		end

		return event.OnClientEvent:Connect(callback)
	end

	function Missions.Describe()
		local module, resolveError = resolve()
		local list = module and Missions.List() or nil

		return {
			Available = module ~= nil,
			Error = resolveError,
			MissionCount = list and #list or 0,
			SupportsQueue =
				module and type(module.RequestQueue) == "function" or false,
			SupportsRewards =
				module and type(module.GetMissionPrize) == "function" or false,
			SupportsFinishChoice =
				module
					and type(module.SetLeaveChoice) == "function"
					and type(module.NotifyReadyToLeave) == "function"
				or false,
		}
	end

	return Missions
end
