return function(ctx)
	local Walkspeed = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript =
			GameContext.FindReplicated("Shared.WalkspeedManager")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_walkspeed_manager_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_walkspeed_manager_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	function Walkspeed.Get(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetWalkspeed) ~= "function" then
			return nil, "shared_walkspeed_missing_get"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local ok, speed =
			pcall(module.GetWalkspeed, module, character)
		speed = tonumber(speed)

		if not ok or not speed then
			return nil, "walkspeed_value_unavailable"
		end

		return speed
	end

	function Walkspeed.ApplyMultiplier(key, multiplier, character)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.AddWalkspeedMultiplier) ~= "function" then
			return false, "shared_walkspeed_missing_add_multiplier"
		end

		character = character or GameContext.GetCharacter()
		multiplier = tonumber(multiplier)

		if not character then
			return false, "character_unavailable"
		end

		if type(key) ~= "string" or key == "" then
			return false, "multiplier_key_required"
		end

		if not multiplier or multiplier <= 0 then
			return false, "invalid_walkspeed_multiplier"
		end

		local ok, applyError = pcall(
			module.AddWalkspeedMultiplier,
			module,
			character,
			key,
			multiplier
		)

		if not ok then
			return false, "walkspeed_multiplier_failed:" .. tostring(applyError)
		end

		return true
	end

	function Walkspeed.RemoveMultiplier(key, character)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.RemoveWalkspeedMultiplier) ~= "function" then
			return false, "shared_walkspeed_missing_remove_multiplier"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return false, "character_unavailable"
		end

		local ok = pcall(
			module.RemoveWalkspeedMultiplier,
			module,
			character,
			key
		)

		if not ok then
			return false, "walkspeed_remove_multiplier_failed"
		end

		return true
	end

	function Walkspeed.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasGet = module
				and type(module.GetWalkspeed) == "function"
				or false,
			HasMultipliers = module
				and type(module.AddWalkspeedMultiplier) == "function"
				and type(module.RemoveWalkspeedMultiplier) == "function"
				or false,
		}
	end

	return Walkspeed
end
