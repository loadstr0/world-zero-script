return function(ctx)
	local Quests = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local Players = ctx.Services.Players
	local ReplicatedStorage = ctx.Services.ReplicatedStorage
	local cachedModule = nil
	local cachedMainCandidates = nil
	local cachedMainCandidatesWorld = nil
	local cachedMainCandidatesAt = 0
	local DUNGEON_OBJECTIVES = {
		DoDungeon = true,
		DoDungeonWithDifficulty = true,
		DoDungeonWithWorldAndDifficulty = true,
		DoDungeonInWorld = true,
		DoRandomDungeonWithDifficulty = true,
		DoRandomDungeonWithDifficultyAndGuild = true,
		DoThisDungeonWithFriends = true,
		DoDungeonWithFriends = true,
		DoDungeonWithGuild = true,
		DoDungeonWithOthers = true,
	}

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Quests")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_quests_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_quests_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	local function call(methodName, ...)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		local method = module[methodName]

		if type(method) ~= "function" then
			return nil, "shared_quests_missing_" .. string.lower(methodName)
		end

		local packed = table.pack(pcall(method, module, ...))

		if not packed[1] then
			return nil, "shared_quests_call_failed_" .. string.lower(methodName)
		end

		return table.unpack(packed, 2, packed.n)
	end

	local function appendDirectory(result, seen, directory)
		if not directory then
			return
		end

		for _, quest in ipairs(directory:GetChildren()) do
			local id = tonumber(quest.Name)

			if id and not seen[id] then
				seen[id] = true
				table.insert(result, {
					ID = id,
					Instance = quest,
					ReadyToClaim = quest:FindFirstChild("Completed") ~= nil,
				})
			end
		end
	end

	local function getActiveInstances()
		local profile, profileError = Profile.Get()

		if not profile then
			return nil, profileError
		end

		local result = {}
		local seen = {}
		local quests = profile:FindFirstChild("Quests")

		appendDirectory(result, seen, quests and quests:FindFirstChild("Active"))

		local eventData = profile:FindFirstChild("EventData")

		if eventData then
			for _, event in ipairs(eventData:GetChildren()) do
				local eventQuests = event:FindFirstChild("Quests")

				appendDirectory(result, seen, eventQuests and eventQuests:FindFirstChild("Active"))
			end
		end

		table.sort(result, function(a, b)
			if a.ReadyToClaim ~= b.ReadyToClaim then
				return a.ReadyToClaim
			end

			return a.ID < b.ID
		end)

		return result
	end

	local function getLocation(data)
		local reference = data and data.ref

		if type(reference) ~= "string" or reference == "" then
			return nil, "quest_reference_unavailable"
		end

		local locations = ReplicatedStorage:FindFirstChild("QuestLocations")
			or workspace:FindFirstChild("QuestLocations")
		local location = locations and locations:FindFirstChild(reference)

		if not location then
			return nil, "quest_location_not_in_current_place"
		end

		local position = nil

		if location:IsA("BasePart") then
			position = location.Position
		elseif location:IsA("Attachment") then
			position = location.WorldPosition
		elseif location:IsA("Model") then
			local part = location.PrimaryPart or location:FindFirstChildWhichIsA("BasePart", true)

			position = part and part.Position or nil
		end

		if not position then
			return nil, "quest_location_has_no_position"
		end

		local rangeValue = location:FindFirstChild("Range")
		local range = rangeValue and tonumber(rangeValue.Value) or 100

		return {
			Instance = location,
			Position = position,
			Range = math.max(10, range or 100),
			Reference = reference,
		}
	end

	function Quests.ListActive()
		return getActiveInstances()
	end

	function Quests.GetData(id)
		local data, dataError = call("GetQuestDataFromID", tonumber(id))

		if type(data) ~= "table" then
			return nil, dataError or "quest_data_unavailable"
		end

		return data
	end

	local function getCategory(data)
		if data.FromEvent ~= nil then
			return "Event"
		elseif data.DailyQuest == true then
			return "Daily"
		elseif data.WeeklyQuest == true then
			return "Weekly"
		elseif data.GuildWeeklyQuest == true then
			return "Guild"
		elseif data.WorldQuest == true then
			return "Main"
		end

		return "Side"
	end

	local function isStoryQuest(data)
		return type(data) == "table"
			and data.WorldQuest == true
			and data.FromEvent == nil
			and data.DailyQuest ~= true
			and data.WeeklyQuest ~= true
			and data.GuildWeeklyQuest ~= true
			and data.DailyGuildQuest ~= true
	end

	local function getMainCandidates(currentWorldOrder)
		local cacheWorld = tonumber(currentWorldOrder)
		local now = os.clock()

		if
			cachedMainCandidates
			and cachedMainCandidatesWorld == cacheWorld
			and now - cachedMainCandidatesAt < 0.75
		then
			return cachedMainCandidates
		end

		local questList, listError = call("GetQuestList")

		if type(questList) ~= "table" then
			return nil, listError or "quest_list_unavailable"
		end

		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local candidates = {}

		for rawID, data in pairs(questList) do
			local id = tonumber(rawID)

			if id and isStoryQuest(data) and data.Disabled ~= true and data.HideFromQuestList ~= true then
				local progress, alreadyClaimed = call("GetQuestProgress", player, id)
				local required = tonumber(type(data.Objective) == "table" and data.Objective[2]) or 0
				local readyToClaim = call("QuestCompleted", player, id) == true

				if not readyToClaim and required > 0 and tonumber(progress) and tonumber(progress) >= required then
					readyToClaim = true
				end

				if alreadyClaimed ~= true then
					table.insert(candidates, {
						ID = id,
						Data = data,
						IsMain = true,
						IsTracked = false,
						IsCurrentWorld = tonumber(currentWorldOrder) ~= nil
							and tonumber(data.LinkedWorld) == tonumber(currentWorldOrder),
						Priority = tonumber(data.Priority) or math.huge,
						Progress = tonumber(progress) or 0,
						Required = required,
						ReadyToClaim = readyToClaim,
						AlreadyClaimed = false,
						LinkedWorld = tonumber(data.LinkedWorld),
						Source = "StoryCatalog",
					})
				end
			end
		end

		table.sort(candidates, function(a, b)
			if a.ReadyToClaim ~= b.ReadyToClaim then
				return a.ReadyToClaim
			end

			local aWorld = a.LinkedWorld or math.huge
			local bWorld = b.LinkedWorld or math.huge

			if aWorld ~= bWorld then
				return aWorld < bWorld
			elseif a.Priority ~= b.Priority then
				return a.Priority < b.Priority
			end

			return a.ID < b.ID
		end)

		cachedMainCandidates = candidates
		cachedMainCandidatesWorld = cacheWorld
		cachedMainCandidatesAt = now

		return candidates
	end

	function Quests.ListMainCandidates(currentWorldOrder)
		return getMainCandidates(currentWorldOrder)
	end

	function Quests.GetSelectedID(currentWorldOrder)
		local mainCandidates, mainError = getMainCandidates(currentWorldOrder)

		if mainCandidates and mainCandidates[1] then
			return mainCandidates[1].ID, nil, mainCandidates[1]
		end

		local active, activeError = getActiveInstances()

		if not active then
			return nil, activeError or mainError
		end

		local profile = Profile.Get()
		local tracking = profile and profile:FindFirstChild("TrackingQuest")
		local trackedID = tracking and tonumber(tracking.Value) or 0

		for _, entry in ipairs(active) do
			entry.Data = Quests.GetData(entry.ID) or {}
			entry.IsMain = isStoryQuest(entry.Data)
			entry.IsTracked = entry.ID == trackedID
			entry.IsCurrentWorld = tonumber(currentWorldOrder) ~= nil
				and tonumber(entry.Data.LinkedWorld) == tonumber(currentWorldOrder)
			entry.Priority = tonumber(entry.Data.Priority) or 0
			entry.Source = "ActiveProfile"
		end

		table.sort(active, function(a, b)
			if a.IsMain ~= b.IsMain then
				return a.IsMain
			elseif a.IsCurrentWorld ~= b.IsCurrentWorld then
				return a.IsCurrentWorld
			elseif a.IsTracked ~= b.IsTracked then
				return a.IsTracked
			elseif a.ReadyToClaim ~= b.ReadyToClaim then
				return a.ReadyToClaim
			elseif a.Priority ~= b.Priority then
				return a.Priority > b.Priority
			end

			return a.ID < b.ID
		end)

		if active[1] then
			return active[1].ID, nil, active[1]
		end

		return nil, "no_active_quest"
	end

	function Quests.GetCurrent(currentWorldOrder)
		local id, idError, selection = Quests.GetSelectedID(currentWorldOrder)

		if not id then
			return nil, idError
		end

		local data, dataError = Quests.GetData(id)

		if not data then
			return nil, dataError
		end

		local player = Players.LocalPlayer
		local progress = selection and selection.Progress
		local alreadyClaimed = selection and selection.AlreadyClaimed
		local readyToClaim = selection and selection.ReadyToClaim

		if progress == nil or alreadyClaimed == nil then
			progress, alreadyClaimed = call("GetQuestProgress", player, id)
		end

		if readyToClaim == nil then
			readyToClaim = call("QuestCompleted", player, id) == true
		end
		local objective = type(data.Objective) == "table" and data.Objective or {}
		local allowedMobNames = {}

		if objective[1] == "KillMob" and type(objective[3]) == "table" then
			for _, name in ipairs(objective[3]) do
				if type(name) == "string" and name ~= "" then
					table.insert(allowedMobNames, name)
				end
			end
		end

		local location, locationError = getLocation(data)
		local objectiveType = tostring(objective[1] or "Unknown")
		local arguments = type(objective[3]) == "table" and objective[3] or {}
		local isDungeonObjective = DUNGEON_OBJECTIVES[objectiveType] == true
		local destinationWorldOrder = objectiveType == "WorldJoin"
				and tonumber(arguments[1])
			or nil
		local exactDungeon = objectiveType == "DoDungeon"
			or objectiveType == "DoDungeonWithDifficulty"
			or objectiveType == "DoThisDungeonWithFriends"
		local dungeonID = exactDungeon and tonumber(arguments[1]) or nil
		local dungeonDifficulty = 1

		if objectiveType == "DoDungeonWithDifficulty" or objectiveType == "DoThisDungeonWithFriends" then
			dungeonDifficulty = tonumber(arguments[2]) or 1
		elseif
			objectiveType == "DoDungeonWithWorldAndDifficulty"
			or objectiveType == "DoRandomDungeonWithDifficulty"
			or objectiveType == "DoRandomDungeonWithDifficultyAndGuild"
		then
			dungeonDifficulty = tonumber(arguments[1]) or 1
		elseif exactDungeon then
			dungeonDifficulty = tonumber(arguments[2]) or 1
		end

		return {
			ID = id,
			Name = tostring(data.NameTag or data.Name or data.Title or ("Quest " .. tostring(id))),
			Data = data,
			ObjectiveType = objectiveType,
			Required = tonumber(objective[2]) or 0,
			Arguments = arguments,
			IsDungeonObjective = isDungeonObjective,
			DungeonID = dungeonID,
			DungeonDifficulty = dungeonDifficulty,
			DestinationWorldOrder = destinationWorldOrder,
			AllowedMobNames = allowedMobNames,
			Progress = tonumber(progress) or 0,
			ReadyToClaim = readyToClaim,
			AlreadyClaimed = alreadyClaimed == true,
			IsMain = isStoryQuest(data),
			Category = getCategory(data),
			LinkedWorld = tonumber(data.LinkedWorld),
			IsTracked = selection and selection.IsTracked == true,
			Location = location,
			LocationError = locationError,
			Reference = data.ref,
			SelectionSource = selection and selection.Source or "Unknown",
		}
	end

	function Quests.Claim(id)
		local player = Players.LocalPlayer

		if not player then
			return false, "local_player_unavailable"
		end

		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.ClaimQuest) ~= "function" then
			return false, "shared_quests_missing_claimquest"
		end

		local ok, claimError = pcall(module.ClaimQuest, module, player, tonumber(id))

		if not ok then
			return false, "quest_claim_failed:" .. tostring(claimError)
		end

		cachedMainCandidates = nil
		cachedMainCandidatesAt = 0

		return true
	end

	function Quests.SetTracking(id)
		local player = Players.LocalPlayer
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.SetTrackingQuest) ~= "function" then
			return false, "shared_quests_missing_settrackingquest"
		end

		local ok, trackingError = pcall(module.SetTrackingQuest, module, player, tonumber(id))

		if not ok then
			return false, "quest_tracking_failed:" .. tostring(trackingError)
		end

		return true
	end

	function Quests.ObserveUpdated(callback)
		local signal, signalError = call("GetQuestUpdatedSignal")

		if not signal or type(signal.Connect) ~= "function" then
			return nil, signalError or "quest_updated_signal_unavailable"
		end

		return signal:Connect(callback)
	end

	function Quests.Describe()
		local module, resolveError = resolve()
		local active = module and getActiveInstances() or nil
		local mainCandidates = module and getMainCandidates() or nil

		return {
			Available = module ~= nil,
			Error = resolveError,
			ActiveCount = type(active) == "table" and #active or 0,
			MainCandidateCount = type(mainCandidates) == "table" and #mainCandidates or 0,
			SupportsClaim = module and type(module.ClaimQuest) == "function" or false,
			SupportsTracking = module and type(module.SetTrackingQuest) == "function" or false,
		}
	end

	return Quests
end
