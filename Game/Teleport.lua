return function(ctx)
	local Teleport = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local Players = ctx.Services.Players
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript =
			GameContext.FindReplicated("Shared.Teleport")

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

	function Teleport.ListWorlds()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetLocations) ~= "function" then
			return nil, "teleport_missing_locations"
		end

		local ok, locations =
			pcall(module.GetLocations, module)

		if not ok or type(locations) ~= "table" then
			return nil, "world_locations_unavailable"
		end

		local result = {}

		for key, data in pairs(locations) do
			if type(data) == "table" and isActiveDestination(data) then
				local id = tonumber(data.ID) or tonumber(key)

				if id then
					local name =
						tostring(data.Name or data.NameTag or ("World " .. id))
					local subtext =
						type(data.Subtext) == "string"
							and data.Subtext ~= ""
							and data.Subtext
						or nil
					local label = name

					if subtext and subtext ~= name then
						label = label .. " - " .. subtext
					end

					label = label .. " [" .. tostring(id) .. "]"

					table.insert(result, {
						ID = id,
						Name = name,
						Label = label,
						WorldOrderID =
							tonumber(data.WorldOrderID) or 9999,
						LevelRequirement =
							tonumber(data.LevelRequirement) or 1,
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

	function Teleport.GetCurrentWorld()
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetCurrentWorldData) ~= "function" then
			return nil, "teleport_missing_current_world"
		end

		local ok, data =
			pcall(module.GetCurrentWorldData, module)

		if not ok then
			return nil, "current_world_query_failed"
		end

		return data
	end

	function Teleport.ToWorld(worldId)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.TeleportToWorld) ~= "function" then
			return false, "teleport_missing_world_request"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local ok, travelError = pcall(
			module.TeleportToWorld,
			module,
			player,
			tonumber(worldId)
		)

		if not ok then
			return false, "world_teleport_failed:" .. tostring(travelError)
		end

		return true
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
			destinationId =
				current and tonumber(current.ID) or nil
		end

		if not destinationId then
			return false, "hub_destination_unavailable"
		end

		local ok, travelError = pcall(
			module.TeleportToHub,
			module,
			player,
			destinationId
		)

		if not ok then
			return false, "hub_teleport_failed:" .. tostring(travelError)
		end

		return true
	end

	function Teleport.ToMission(missionId, difficultyId)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.TeleportToMission) ~= "function" then
			return false, "teleport_missing_mission_request"
		end

		local player = getPlayer()

		if not player then
			return false, "local_player_unavailable"
		end

		local ok, travelError = pcall(
			module.TeleportToMission,
			module,
			player,
			tonumber(missionId),
			tonumber(difficultyId) or 1
		)

		if not ok then
			return false, "mission_teleport_failed:" .. tostring(travelError)
		end

		return true
	end

	function Teleport.Describe()
		local module, resolveError = resolve()
		local worlds = module and Teleport.ListWorlds() or nil

		return {
			Available = module ~= nil,
			Error = resolveError,
			WorldCount = worlds and #worlds or 0,
			SupportsWorldTravel =
				module and type(module.TeleportToWorld) == "function" or false,
			SupportsMissionTravel =
				module
					and type(module.TeleportToMission) == "function"
				or false,
		}
	end

	return Teleport
end
