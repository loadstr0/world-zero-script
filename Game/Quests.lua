return function(ctx)
	local Quests = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local Players = ctx.Services.Players
	local ReplicatedStorage = ctx.Services.ReplicatedStorage
	local cachedModule = nil

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
			return nil
		end

		local locations = ReplicatedStorage:FindFirstChild("QuestLocations")
			or workspace:FindFirstChild("QuestLocations")
		local location = locations and locations:FindFirstChild(reference)

		if not location then
			return nil
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
			return nil
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

	function Quests.GetSelectedID()
		local active, activeError = getActiveInstances()

		if not active then
			return nil, activeError
		end

		local profile = Profile.Get()
		local tracking = profile and profile:FindFirstChild("TrackingQuest")
		local trackedID = tracking and tonumber(tracking.Value) or 0

		if trackedID > 0 then
			for _, entry in ipairs(active) do
				if entry.ID == trackedID then
					return trackedID
				end
			end
		end

		if active[1] then
			return active[1].ID
		end

		return nil, "no_active_quest"
	end

	function Quests.GetCurrent()
		local id, idError = Quests.GetSelectedID()

		if not id then
			return nil, idError
		end

		local data, dataError = Quests.GetData(id)

		if not data then
			return nil, dataError
		end

		local player = Players.LocalPlayer
		local progress, alreadyClaimed = call("GetQuestProgress", player, id)
		local readyToClaim = call("QuestCompleted", player, id) == true
		local objective = type(data.Objective) == "table" and data.Objective or {}
		local allowedMobNames = {}

		if objective[1] == "KillMob" and type(objective[3]) == "table" then
			for _, name in ipairs(objective[3]) do
				if type(name) == "string" and name ~= "" then
					table.insert(allowedMobNames, name)
				end
			end
		end

		return {
			ID = id,
			Name = tostring(data.NameTag or data.Name or data.Title or ("Quest " .. tostring(id))),
			Data = data,
			ObjectiveType = tostring(objective[1] or "Unknown"),
			Required = tonumber(objective[2]) or 0,
			Arguments = objective[3],
			AllowedMobNames = allowedMobNames,
			Progress = tonumber(progress) or 0,
			ReadyToClaim = readyToClaim,
			AlreadyClaimed = alreadyClaimed == true,
			Location = getLocation(data),
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

		return {
			Available = module ~= nil,
			Error = resolveError,
			ActiveCount = type(active) == "table" and #active or 0,
			SupportsClaim = module and type(module.ClaimQuest) == "function" or false,
			SupportsTracking = module and type(module.SetTrackingQuest) == "function" or false,
		}
	end

	return Quests
end
