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

		-- The queued script re-queues itself as soon as the destination starts.
		-- Avoid adding a second copy later in the same server, since some
		-- executors append queue entries instead of replacing them.
		if currentJobId ~= "" and env.WorldZeroTeleportQueueJobId == currentJobId then
			return true
		end

		local bootstrapBase = ctx.Base
		local loadedCommit = env.WorldZeroLoadedCommit

		if
			type(loadedCommit) == "string"
			and #loadedCommit >= 7
			and string.match(loadedCommit, "^[%da-fA-F]+$")
		then
			bootstrapBase = "https://raw.githubusercontent.com/loadstr0/world-zero-script/"
				.. loadedCommit
				.. "/"
		end

		local bootstrapUrl = bootstrapBase
			.. "Bootstrap.lua?cache="
			.. tostring(os.time())
			.. tostring(math.random(1000, 9999))
		local resumeState = {}
		local runtime = ctx.ActiveRuntime

		for key, value in pairs(runtime and runtime.State and runtime.State.Values or {}) do
			local valueType = type(value)

			if type(key) == "string" and (valueType == "boolean" or valueType == "number" or valueType == "string") then
				resumeState[key] = value
			end
		end

		local encodedResume = HttpService:JSONEncode({
			Version = 3,
			QueuedAt = os.time(),
			State = resumeState,
		})
		local body = "local env = getgenv()"
			.. "\nenv.WorldZeroTeleportResume = "
			.. string.format("%q", encodedResume)
			.. "\nenv.WorldZeroBase = "
			.. string.format("%q", bootstrapBase)
			.. "\nenv.WorldZeroPinLatestCommit = false"
			.. "\nlocal jobId = tostring(game.JobId or \"\")"
			.. "\nlocal queuedSource = \"local body = \" .. string.format(\"%q\", body) .. \"\\n\" .. body"
			.. "\nlocal queue = queue_on_teleport or (type(syn) == \"table\" and syn.queue_on_teleport)"
			.. "\nif type(queue) == \"function\" and env.WorldZeroTeleportQueueJobId ~= jobId then"
			.. "\n  local queued = pcall(queue, queuedSource)"
			.. "\n  if queued then env.WorldZeroTeleportQueueJobId = jobId end"
			.. "\nend"
			.. "\nif env.WorldZeroTeleportBootJobId == jobId then return end"
			.. "\nenv.WorldZeroTeleportBootJobId = jobId"
			.. "\nif not game:IsLoaded() then game.Loaded:Wait() end"
			.. "\nrepeat task.wait(0.1) until game:GetService(\"Players\").LocalPlayer"
			.. "\nfor attempt = 1, 30 do"
			.. "\n  local context = env.WorldZeroRuntime or env.WorldZeroContext"
			.. "\n  if context and context.ActiveRuntime and not context.ActiveRuntime.Stopped then break end"
			.. "\n  local url = "
			.. string.format("%q", bootstrapUrl)
			.. " .. \"&attempt=\" .. tostring(attempt)"
			.. "\n  local downloaded, source = pcall(game.HttpGet, game, url)"
			.. "\n  if downloaded and type(source) == \"string\" then"
			.. "\n    local chunk = loadstring(source)"
			.. "\n    if chunk then pcall(chunk) end"
			.. "\n  end"
			.. "\n  context = env.WorldZeroRuntime or env.WorldZeroContext"
			.. "\n  if context and context.ActiveRuntime and not context.ActiveRuntime.Stopped then break end"
			.. "\n  task.wait(math.min(1 + attempt * 0.25, 4))"
			.. "\nend"
		local source = "local body = " .. string.format("%q", body) .. "\n" .. body
		local ok, queueError = pcall(Executor.QueueOnTeleport, source)

		if not ok then
			return false, "queue_on_teleport_failed:" .. tostring(queueError)
		end

		if currentJobId ~= "" then
			env.WorldZeroTeleportQueueJobId = currentJobId
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
