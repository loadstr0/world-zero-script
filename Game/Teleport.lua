return function(ctx)
	local Teleport = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local Executor = ctx:Require("Executor")
	local Players = ctx.Services.Players
	local HttpService = ctx.Services.HttpService
	local env = getgenv()
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Teleport")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_teleport_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_teleport_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	local function getPlayer()
		return Players.LocalPlayer
	end

	function Teleport.QueueBootstrap()
		if type(Executor.QueueOnTeleport) ~= "function" then
			return false, "queue_on_teleport_unavailable"
		end

		local currentJobId = tostring(game.JobId or "")
		local loadedCommit = env.WorldZeroLoadedCommit
		local baseCommit =
			string.match(tostring(ctx.Base or ""), "/world%-zero%-script/([%da-fA-F]+)/")
		-- ctx.Base identifies the immutable source that produced this runtime.
		-- The asynchronous update check can change WorldZeroLoadedCommit after
		-- startup, so preferring that label could queue a different generation
		-- than the modules that are actually running.
		local desiredCommit = baseCommit
			or (type(loadedCommit) == "string" and loadedCommit)
			or ""

		local bootstrapBase = ctx.Base

		if #desiredCommit >= 7 and string.match(desiredCommit, "^[%da-fA-F]+$") then
			bootstrapBase = "https://raw.githubusercontent.com/loadstr0/world-zero-script/"
				.. desiredCommit
				.. "/"
		end

		local bootstrapUrl = bootstrapBase
			.. "Bootstrap.lua?cache="
			.. tostring(os.time())
			.. tostring(math.random(1000, 9999))
		local resumeState = {}
		local runtime = ctx.ActiveRuntime
		local signatureEntries = {}

		for key, value in pairs(runtime and runtime.State and runtime.State.Values or {}) do
			local valueType = type(value)

			if type(key) == "string" and (valueType == "boolean" or valueType == "number" or valueType == "string") then
				resumeState[key] = value
				table.insert(signatureEntries, HttpService:JSONEncode({ key, value }))
			end
		end

		table.sort(signatureEntries)
		local resumeSignature = table.concat(signatureEntries, "\n")
		local encodedResume = HttpService:JSONEncode({
			Version = 3,
			QueuedAt = os.time(),
			State = resumeState,
		})

		-- A control can change long after startup. Only keep the existing queue
		-- when both its source generation and its complete saved state still
		-- match; otherwise replace it so a server hop cannot resurrect stale
		-- automation toggles.
		if
			currentJobId ~= ""
			and env.WorldZeroTeleportQueueJobId == currentJobId
			and tostring(env.WorldZeroTeleportQueueCommit or "") == desiredCommit
			and tostring(env.WorldZeroTeleportQueueStateSignature or "") == resumeSignature
		then
			return true
		end

		local queueVersion = os.time() * 100000 + math.random(10000, 99999)
		local queueCommit = desiredCommit
		local body = "local env = getgenv()"
			.. "\nlocal candidateVersion = "
			.. tostring(queueVersion)
			.. "\nlocal currentVersion = tonumber(env.WorldZeroTeleportQueueVersion) or 0"
			.. "\nif currentVersion > candidateVersion then return end"
			.. "\nenv.WorldZeroTeleportQueueVersion = candidateVersion"
			.. "\nenv.WorldZeroTeleportQueueCommit = "
			.. string.format("%q", queueCommit)
			.. "\nenv.WorldZeroTeleportQueueStateSignature = "
			.. string.format("%q", resumeSignature)
			.. "\nenv.WorldZeroTeleportResume = "
			.. string.format("%q", encodedResume)
			.. "\nenv.WorldZeroBase = "
			.. string.format("%q", bootstrapBase)
			.. "\nenv.WorldZeroPinLatestCommit = false"
			.. "\nlocal jobId = tostring(game.JobId or \"\")"
			.. "\nlocal queuedSource = \"local body = \" .. string.format(\"%q\", body) .. \"\\n\" .. body"
			.. "\nlocal queue = queue_on_teleport or (type(syn) == \"table\" and syn.queue_on_teleport)"
			.. "\nlocal queueToken = jobId .. \":\" .. tostring(candidateVersion)"
			.. "\nif type(queue) == \"function\" and env.WorldZeroTeleportQueueToken ~= queueToken then"
			.. "\n  local queued = pcall(queue, queuedSource)"
			.. "\n  if queued then"
			.. "\n    env.WorldZeroTeleportQueueToken = queueToken"
			.. "\n    env.WorldZeroTeleportQueueJobId = jobId"
			.. "\n  end"
			.. "\nend"
			.. "\nlocal bootToken = jobId .. \":\" .. tostring(candidateVersion)"
			.. "\nif env.WorldZeroTeleportBootToken == bootToken then return end"
			.. "\nif (tonumber(env.WorldZeroTeleportBootVersion) or 0) > candidateVersion then return end"
			.. "\nenv.WorldZeroTeleportBootVersion = candidateVersion"
			.. "\nenv.WorldZeroTeleportBootToken = bootToken"
			.. "\nenv.WorldZeroTeleportBootJobId = jobId"
			.. "\nif not game:IsLoaded() then game.Loaded:Wait() end"
			.. "\nrepeat task.wait(0.1) until game:GetService(\"Players\").LocalPlayer"
			.. "\nfor attempt = 1, 30 do"
			.. "\n  if (tonumber(env.WorldZeroTeleportQueueVersion) or 0) > candidateVersion then return end"
			.. "\n  local context = env.WorldZeroRuntime or env.WorldZeroContext"
			.. "\n  if context and context.ActiveRuntime and not context.ActiveRuntime.Stopped"
			.. " and ("
			.. string.format("%q", queueCommit)
			.. " == \"\" or string.sub(tostring(env.WorldZeroLoadedCommit or \"\"), 1, #"
			.. string.format("%q", queueCommit)
			.. ") == "
			.. string.format("%q", queueCommit)
			.. ") then break end"
			.. "\n  local url = "
			.. string.format("%q", bootstrapUrl)
			.. " .. \"&attempt=\" .. tostring(attempt)"
			.. "\n  local downloaded, source = pcall(game.HttpGet, game, url)"
			.. "\n  if downloaded and type(source) == \"string\" then"
			.. "\n    local chunk = loadstring(source)"
			.. "\n    if chunk then pcall(chunk) end"
			.. "\n  end"
			.. "\n  context = env.WorldZeroRuntime or env.WorldZeroContext"
			.. "\n  if context and context.ActiveRuntime and not context.ActiveRuntime.Stopped"
			.. " and ("
			.. string.format("%q", queueCommit)
			.. " == \"\" or string.sub(tostring(env.WorldZeroLoadedCommit or \"\"), 1, #"
			.. string.format("%q", queueCommit)
			.. ") == "
			.. string.format("%q", queueCommit)
			.. ") then break end"
			.. "\n  task.wait(math.min(1 + attempt * 0.25, 4))"
			.. "\nend"
		local source = "local body = " .. string.format("%q", body) .. "\n" .. body

		-- Remove stale self-requeuing payloads from older releases before
		-- installing the single elected generation. Executors that append
		-- queue entries would otherwise launch several loaders after a hop.
		if type(Executor.ClearTeleportQueue) == "function" then
			pcall(Executor.ClearTeleportQueue)
		end

		local ok, queueError = pcall(Executor.QueueOnTeleport, source)

		if not ok then
			return false, "queue_on_teleport_failed:" .. tostring(queueError)
		end

		if currentJobId ~= "" then
			env.WorldZeroTeleportQueueJobId = currentJobId
			env.WorldZeroTeleportQueueCommit = queueCommit
			env.WorldZeroTeleportQueueStateSignature = resumeSignature
			env.WorldZeroTeleportQueueVersion = queueVersion
			env.WorldZeroTeleportQueueToken = currentJobId .. ":" .. tostring(queueVersion)
		end

		return true
	end

	local function isActiveDestination(data)
		local now = os.time()
		local starts = tonumber(data.StartTime)
		local ends = tonumber(data.LimitedTime)

		return data.CanTeleport == true
			and data.Disabled ~= true
			and data.HiddenOnProduction ~= true
			and (not starts or starts <= now)
			and (not ends or now <= ends)
	end

	local function getKind(data)
		local worldOrder = tonumber(data.WorldOrderID) or 0

		if data.IsTown == true and worldOrder >= 100 then
			return "Event Hub"
		elseif data.IsTown == true then
			return "Hub"
		elseif data.IsOpenWorld == true and worldOrder >= 100 then
			return "Event World"
		elseif data.IsOpenWorld == true then
			return "Open World"
		elseif data.IsOtherWorld == true then
			return "Special"
		end

		return "Destination"
	end

	function Teleport.ListWorlds()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetLocations) ~= "function" then
			return nil, "teleport_missing_locations"
		end

		local ok, locations = pcall(module.GetLocations, module)

		if not ok or type(locations) ~= "table" then
			return nil, "world_locations_unavailable"
		end

		local result = {}

		for key, data in pairs(locations) do
			if type(data) == "table" and isActiveDestination(data) then
				local id = tonumber(data.ID) or tonumber(key)

				if id then
					local name = tostring(data.Name or data.NameTag or ("World " .. id))
					local subtext = type(data.Subtext) == "string" and data.Subtext ~= "" and data.Subtext or nil
					local label = name

					if subtext and subtext ~= name then
						label = label .. " - " .. subtext
					end

					label = label .. " [" .. tostring(id) .. "]"

					table.insert(result, {
						ID = id,
						Name = name,
						Label = label,
						WorldOrderID = tonumber(data.WorldOrderID) or 9999,
						LevelRequirement = tonumber(data.LevelRequirement) or 1,
						Kind = getKind(data),
						IsHub = data.IsTown == true,
						IsEvent = (tonumber(data.WorldOrderID) or 0) >= 100,
						Data = data,
					})
				end
			end
		end

		table.sort(result, function(a, b)
			if a.WorldOrderID ~= b.WorldOrderID then
				return a.WorldOrderID < b.WorldOrderID
			end

			return a.ID < b.ID
		end)

		return result
	end

	function Teleport.ListByKind(kind)
		local worlds, worldsError = Teleport.ListWorlds()

		if not worlds then
			return nil, worldsError
		end

		local result = {}

		for _, world in ipairs(worlds) do
			if world.Kind == kind then
				table.insert(result, world)
			end
		end

		return result
	end

	function Teleport.ListHubs(includeEvents)
		local worlds, worldsError = Teleport.ListWorlds()

		if not worlds then
			return nil, worldsError
		end

		local result = {}

		for _, world in ipairs(worlds) do
			if world.IsHub and (includeEvents == true or not world.IsEvent) then
				table.insert(result, world)
			end
		end

		return result
	end

	function Teleport.ListEvents()
		local worlds, worldsError = Teleport.ListWorlds()

		if not worlds then
			return nil, worldsError
		end

		local result = {}

		for _, world in ipairs(worlds) do
			if world.IsEvent then
				table.insert(result, world)
			end
		end

		return result
	end

	function Teleport.GetCurrentWorld()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetCurrentWorldData) ~= "function" then
			return nil, "teleport_missing_current_world"
		end

		local ok, data = pcall(module.GetCurrentWorldData, module)

		if not ok then
			return nil, "current_world_query_failed"
		end

		return data
	end

	function Teleport.GetCurrentWorldOrder()
		local current, currentError = Teleport.GetCurrentWorld()

		if not current then
			return nil, currentError
		end

		return tonumber(current.WorldOrderID) or tonumber(current.ID), nil
	end

	function Teleport.FindOpenWorldByOrder(worldOrder)
		local requested = tonumber(worldOrder)

		if not requested then
			return nil, "invalid_world_order"
		end

		local worlds, worldsError = Teleport.ListWorlds()

		if not worlds then
			return nil, worldsError
		end

		local fallback = nil

		for _, world in ipairs(worlds) do
			if world.WorldOrderID == requested then
				if world.Data.IsOpenWorld == true then
					return world
				elseif world.Data.IsTown == true then
					fallback = fallback or world
				elseif not fallback then
					fallback = world
				end
			end
		end

		return fallback, fallback and nil or "world_destination_unavailable"
	end

	function Teleport.ToWorld(worldId)
		local module, resolveError = resolve()
		local destinationId = tonumber(worldId)

		if not module then
			return false, resolveError
		end

		if type(module.TeleportToWorld) ~= "function" then
			return false, "teleport_missing_world_request"
		elseif not destinationId then
			return false, "invalid_world_id"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local queued, queueError = Teleport.QueueBootstrap()
		local ok, travelError = pcall(module.TeleportToWorld, module, player, destinationId)

		if not ok then
			return false, "world_teleport_failed:" .. tostring(travelError)
		end

		return true, nil, queued, queueError
	end

	function Teleport.ToHub(worldId)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.TeleportToHub) ~= "function" then
			return false, "teleport_missing_hub_request"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local destinationId = tonumber(worldId)

		if not destinationId then
			local logoutId = Profile.GetValue("Logout")
			destinationId = tonumber(logoutId)
		end

		if not destinationId then
			local current = Teleport.GetCurrentWorld()
			destinationId = current and tonumber(current.ID) or nil
		end

		if not destinationId then
			return false, "hub_destination_unavailable"
		end

		local queued, queueError = Teleport.QueueBootstrap()
		local ok, travelError = pcall(module.TeleportToHub, module, player, destinationId)

		if not ok then
			return false, "hub_teleport_failed:" .. tostring(travelError)
		end

		return true, nil, queued, queueError
	end

	function Teleport.ToMission(missionId, difficultyId)
		local module, resolveError = resolve()
		local destinationId = tonumber(missionId)
		local destinationDifficulty = tonumber(difficultyId) or 1

		if not module then
			return false, resolveError
		end

		if type(module.TeleportToMission) ~= "function" then
			return false, "teleport_missing_mission_request"
		elseif not destinationId then
			return false, "invalid_mission_id"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local queued, queueError = Teleport.QueueBootstrap()
		local ok, travelError =
			pcall(module.TeleportToMission, module, player, destinationId, destinationDifficulty)

		if not ok then
			return false, "mission_teleport_failed:" .. tostring(travelError)
		end

		return true, nil, queued, queueError
	end

	function Teleport.Describe()
		local module, resolveError = resolve()
		local worlds = module and Teleport.ListWorlds() or nil

		return {
			Available = module ~= nil,
			Error = resolveError,
			WorldCount = worlds and #worlds or 0,
			HubCount = module and #(Teleport.ListHubs(true) or {}) or 0,
			EventCount = module and #(Teleport.ListEvents() or {}) or 0,
			SupportsWorldTravel = module and type(module.TeleportToWorld) == "function" or false,
			SupportsMissionTravel = module and type(module.TeleportToMission) == "function" or false,
			SupportsQueueOnTeleport = type(Executor.QueueOnTeleport) == "function",
		}
	end

	return Teleport
end
