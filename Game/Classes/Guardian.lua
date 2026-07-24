return function(ctx)
	local Guardian = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Guardian",
		AutomationRange = 30,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 16,
			ConeAngle = 45,
			ComboSteps = 4,
			ComboReset = 1,
			AnimationSpeed = 1.21,
		},
		AggroDraw = {
			Slot = "Skill1",
			AggroRadius = 50,
			DefenseStatus = "AggroDefense",
			DefenseDuration = 8,
			TargetWeight = 3,
		},
		RockSpikes = {
			Slot = "Skill2",
			AnimationSpeed = 1.15,
		},
		SlashFury = {
			Slot = "Skill3",
			CrescentCount = 4,
			MaximumDamageCallbacks = 9,
			ExplosionRadius = 13,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Sword Prison",
			RequiresFullEnergy = true,
			ControlRadius = 40,
			ControlPulseCount = 4,
			ControlPulseInterval = 2,
			StopDuration = 5,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function Guardian.Describe()
		return METADATA
	end

	function Guardian.IsAggroDefenseActive()
		return Status.Has(METADATA.AggroDraw.DefenseStatus)
	end

	function Guardian.GetEnergyState()
		return Energy.GetState()
	end

	function Guardian.IsUltimateReady()
		return Energy.IsFull()
	end

	function Guardian.EnsureUnsheathed()
		local sheathed, sheathedError = Actions.IsSheathed()

		if sheathed == true then
			Actions.Sheath()
			return false, "unsheathing"
		end

		if sheathed == nil then
			return false, sheathedError
		end

		return true
	end

	function Guardian.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Guardian.IsUltimateReady()
		end

		return true
	end

	function Guardian.Use(slot)
		local canUse, reason = Guardian.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Guardian.UsePrimary()
		return Guardian.Use(METADATA.Primary.Slot)
	end

	function Guardian.UseAggroDraw()
		return Guardian.Use(METADATA.AggroDraw.Slot)
	end

	function Guardian.UseRockSpikes()
		return Guardian.Use(METADATA.RockSpikes.Slot)
	end

	function Guardian.UseSlashFury()
		return Guardian.Use(METADATA.SlashFury.Slot)
	end

	function Guardian.UseUltimate()
		return Guardian.Use(METADATA.Ultimate.Slot)
	end

	function Guardian.UseDodge()
		return Guardian.Use(METADATA.Dodge.Slot)
	end

	return Guardian
end
