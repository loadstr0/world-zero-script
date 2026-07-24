return function(ctx)
	local Energy = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Energy")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_energy_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_energy_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	function Energy.GetState(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		if type(module.GetEnergyProperties) ~= "function" then
			return nil, "shared_energy_missing_get_properties"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local ok, properties = pcall(module.GetEnergyProperties, module, character)

		if not ok or type(properties) ~= "table" then
			return nil, "energy_properties_unavailable"
		end

		local energy = properties.Energy
		local maxEnergy = properties.MaxEnergy
		local current = energy and tonumber(energy.Value)
		local maximum = maxEnergy and tonumber(maxEnergy.Value)

		if not current or not maximum or maximum <= 0 then
			return nil, "energy_values_unavailable"
		end

		return {
			Current = current,
			Maximum = maximum,
			Ratio = math.clamp(current / maximum, 0, 1),
			Full = current >= maximum,
		}
	end

	function Energy.IsFull(character)
		local state, stateError = Energy.GetState(character)

		if not state then
			return false, stateError
		end

		return state.Full
	end

	function Energy.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasEnergyProperties = module
				and type(module.GetEnergyProperties) == "function"
				or false,
		}
	end

	return Energy
end
