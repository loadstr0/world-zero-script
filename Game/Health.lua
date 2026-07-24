return function(ctx)
	local Health = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Health")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_health_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_health_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	function Health.GetState(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if
			type(module.GetHealth) ~= "function"
			or type(module.GetMaxHealth) ~= "function"
		then
			return nil, "shared_health_missing_accessors"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local healthOk, current = pcall(module.GetHealth, module, character)
		local maximumOk, maximum = pcall(module.GetMaxHealth, module, character)
		current = tonumber(current)
		maximum = tonumber(maximum)

		if not healthOk or not maximumOk or not current or not maximum or maximum <= 0 then
			return nil, "health_values_unavailable"
		end

		return {
			Current = current,
			Maximum = maximum,
			Ratio = math.clamp(current / maximum, 0, 1),
			Alive = current > 0,
		}
	end

	function Health.GetBarrier(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetBarrier) ~= "function" then
			return nil, "shared_health_missing_get_barrier"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local ok, barrier = pcall(module.GetBarrier, module, character)
		barrier = tonumber(barrier)

		if not ok or not barrier then
			return nil, "barrier_value_unavailable"
		end

		return barrier
	end

	function Health.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasHealthAccessors = module
				and type(module.GetHealth) == "function"
				and type(module.GetMaxHealth) == "function"
				or false,
			HasBarrierAccessor = module and type(module.GetBarrier) == "function" or false,
		}
	end

	return Health
end
