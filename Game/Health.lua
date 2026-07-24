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
		local barrier = 0

		if type(module.GetBarrier) == "function" then
			local barrierOk, barrierValue =
				pcall(module.GetBarrier, module, character)

			if barrierOk then
				barrier = tonumber(barrierValue) or 0
			end
		end

		current = tonumber(current)
		maximum = tonumber(maximum)

		if not healthOk or not maximumOk or not current or not maximum or maximum <= 0 then
			return nil, "health_values_unavailable"
		end

		return {
			Current = current,
			Maximum = maximum,
			Ratio = math.clamp(current / maximum, 0, 1),
			Barrier = math.max(barrier, 0),
			ProtectionRatio = math.clamp(
				(current + math.max(barrier, 0)) / maximum,
				0,
				1
			),
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

	function Health.GetBarrierState(character)
		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local current, barrierError = Health.GetBarrier(character)

		if current == nil then
			return nil, barrierError
		end

		local properties = character:FindFirstChild("HealthProperties")
		local maximumValue =
			properties and properties:FindFirstChild("BarrierMaxHealth")
		local maximum =
			maximumValue and tonumber(maximumValue.Value) or 0

		return {
			Current = current,
			Maximum = maximum,
			Ratio = maximum > 0
					and math.clamp(current / maximum, 0, 1)
				or 0,
			Active = current > 0,
		}
	end

	function Health.IsOutOfCombat(character)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.IsOutOfCombat) ~= "function" then
			return false, "shared_health_missing_out_of_combat"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return false, "character_unavailable"
		end

		local ok, result =
			pcall(module.IsOutOfCombat, module, character)

		if not ok then
			return false, "out_of_combat_query_failed"
		end

		return result == true
	end

	function Health.GetLastDamage(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetLastAttacker) ~= "function" then
			return nil, "shared_health_missing_last_attacker"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local ok, attacker, amount =
			pcall(module.GetLastAttacker, module, character)

		if not ok then
			return nil, "last_damage_query_failed"
		end

		return {
			Attacker = attacker,
			Amount = tonumber(amount) or 0,
		}
	end

	function Health.ObserveHits(callback, character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetHitSignal) ~= "function" then
			return nil, "shared_health_missing_hit_signal"
		end

		if type(callback) ~= "function" then
			return nil, "hit_callback_required"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local signalOk, signal =
			pcall(module.GetHitSignal, module, character)

		if not signalOk or not signal then
			return nil, "health_hit_signal_unavailable"
		end

		local connect = signal.Connect or signal.connect

		if type(connect) ~= "function" then
			return nil, "health_hit_signal_not_connectable"
		end

		local connectionOk, connection =
			pcall(connect, signal, callback)

		if not connectionOk then
			return nil, "health_hit_signal_connect_failed"
		end

		return connection
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
			HasCombatState = module
				and type(module.IsOutOfCombat) == "function"
				or false,
			HasLastDamage = module
				and type(module.GetLastAttacker) == "function"
				or false,
			HasHitSignal = module
				and type(module.GetHitSignal) == "function"
				or false,
		}
	end

	return Health
end
