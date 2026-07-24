return function(ctx)
	local Status = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local MOVEMENT_BLOCKING = {
		Frozen = true,
		FrozenFreezeTag = true,
		FrozenHeartbreak = true,
		Knockdown = true,
		Shock = true,
		Stunned = true,
	}

	local SKILL_BLOCKING = {
		Darkness = true,
		Frozen = true,
		FrozenFreezeTag = true,
		FrozenHeartbreak = true,
		Knockdown = true,
		Shock = true,
		Stunned = true,
	}

	local DEFENSE_DEBUFFS = {
		HuntersMark = true,
		ShockDebuff = true,
		SpiritDebuff = true,
		Vulnerable = true,
	}

	local DEFENSE_BUFFS = {
		Adrenaline = true,
		AggroDefense = true,
		AggroDefensePaladin = true,
		DamageResistance = true,
		DefenseBuff = true,
		DivineDefence = true,
		DualWielderTempo = true,
		LesserDefenseBuff = true,
		LesserDefenseBuffGold = true,
		RingOfJusticeBoost = true,
		RockDefenseBuff = true,
		RockDefenseBuffGold = true,
		SantaPresent = true,
		SeaBubble = true,
		SheepDefenseBuff = true,
		Starforge = true,
		StormcallerUltimateSpeed = true,
	}

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Status")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_status_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_status_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	function Status.Has(statusName, character)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.HasStatus) ~= "function" then
			return false, "shared_status_missing_has_status"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return false, "character_unavailable"
		end

		local ok, result = pcall(module.HasStatus, module, character, statusName)

		if not ok then
			return false, "status_query_failed"
		end

		return result ~= nil and result ~= false
	end

	function Status.GetActive(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local folder = character:FindFirstChild("Status")

		if not folder then
			return {}
		end

		local result = {}

		for _, statusObject in ipairs(folder:GetChildren()) do
			local info = nil
			local remaining = nil

			if type(module.GetStatusInfo) == "function" then
				local infoOk, infoValue =
					pcall(module.GetStatusInfo, module, statusObject.Name)

				if infoOk and type(infoValue) == "table" then
					info = infoValue
				end
			end

			if type(module.GetRemainingTime) == "function" then
				local timeOk, timeValue =
					pcall(module.GetRemainingTime, module, statusObject)

				if timeOk then
					remaining = tonumber(timeValue)
				end
			end

			table.insert(result, {
				Name = statusObject.Name,
				Info = info,
				Remaining = remaining,
				Object = statusObject,
			})
		end

		table.sort(result, function(a, b)
			return a.Name < b.Name
		end)

		return result
	end

	local function analyzeActive(active)
		local state = {
			Active = active,
			Count = #active,
			BuffCount = 0,
			DebuffCount = 0,
			MovementBlocked = false,
			SkillsBlocked = false,
			HealingBlocked = false,
			PetDisabled = false,
			HasDamageOverTime = false,
			DamagePerSecond = 0,
			HasHealingOverTime = false,
			HealingPerSecond = 0,
			HasDefenseDebuff = false,
			HasDefenseBuff = false,
			HasFatalStatus = false,
			SeverelySlowed = false,
			WalkspeedMultiplier = 1,
			BlockingStatus = nil,
		}

		for _, status in ipairs(active) do
			local info = status.Info or {}
			local speedMultiplier =
				tonumber(info.WalkspeedMultiplier)
			local damage = tonumber(info.Damage)
			local healing = tonumber(info.Heal)

			if info.IsBuff == true then
				state.BuffCount = state.BuffCount + 1
			else
				state.DebuffCount = state.DebuffCount + 1
			end

			if speedMultiplier then
				state.WalkspeedMultiplier =
					state.WalkspeedMultiplier * speedMultiplier

				if speedMultiplier <= 0.35 then
					state.SeverelySlowed = true
				end
			end

			if
				damage
				and damage > 0
				and info.IsBuff ~= true
			then
				state.HasDamageOverTime = true
				state.DamagePerSecond =
					state.DamagePerSecond + damage
			end

			if healing and healing > 0 then
				state.HasHealingOverTime = true
				state.HealingPerSecond =
					state.HealingPerSecond + healing
			end

			if
				MOVEMENT_BLOCKING[status.Name]
				or speedMultiplier == 0
			then
				state.MovementBlocked = true
				state.BlockingStatus =
					state.BlockingStatus or status.Name
			end

			if SKILL_BLOCKING[status.Name] then
				state.SkillsBlocked = true
				state.BlockingStatus =
					state.BlockingStatus or status.Name
			end

			if status.Name == "Poison" then
				state.HealingBlocked = true
			end

			if status.Name == "DeathMark" then
				state.HasFatalStatus = true
			end

			if
				info.PetDisabled == true
				or status.Name == "PetShackle"
			then
				state.PetDisabled = true
			end

			if DEFENSE_DEBUFFS[status.Name] then
				state.HasDefenseDebuff = true
			end

			if
				DEFENSE_BUFFS[status.Name]
				or (
					info.IsBuff == true
					and tonumber(info.DefenseMultiplier) ~= nil
				)
			then
				state.HasDefenseBuff = true
			end
		end

		state.Dangerous =
			state.HasDamageOverTime
			or state.HasDefenseDebuff
			or state.HasFatalStatus
			or state.MovementBlocked
			or state.SkillsBlocked

		return state
	end

	function Status.GetAutomationState(character)
		local active, activeError = Status.GetActive(character)

		if not active then
			return nil, activeError
		end

		return analyzeActive(active)
	end

	function Status.IsIncapacitated(character)
		local state, stateError =
			Status.GetAutomationState(character)

		if not state then
			return false, stateError
		end

		return state.MovementBlocked, state.BlockingStatus
	end

	function Status.GetSummary(character)
		local active, activeError = Status.GetActive(character)

		if not active then
			return nil, activeError
		end

		local names = {}

		for _, status in ipairs(active) do
			table.insert(names, status.Name)
		end

		local analysis = analyzeActive(active)

		return {
			Count = #active,
			Names = names,
			Text = #names > 0 and table.concat(names, ", ") or "none",
			Analysis = analysis,
		}
	end

	function Status.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasStatusQuery = module and type(module.HasStatus) == "function" or false,
			HasStatusListing = true,
			HasStatusInfo = module
				and type(module.GetStatusInfo) == "function"
				or false,
			HasRemainingTime = module
				and type(module.GetRemainingTime) == "function"
				or false,
			HasSourceBackedAutomationAnalysis = true,
		}
	end

	return Status
end
