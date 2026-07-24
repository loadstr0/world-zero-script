return function(ctx)
	local Demon = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")

	local METADATA = {
		ClassName = "Demon",
		AutomationRange = 60,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 8,
			ComboReset = 1,
		},
		DarkBinding = {
			Slot = "Skill1",
			HealthCost = 0.3,
			DamageBonus = 0.25,
			Duration = 8,
			EnergyGain = 0.04,
		},
		ScytheThrow = {
			Slot = "Skill2",
			InitialRange = 60,
			ChainRange = 40,
			MaxTargets = 8,
		},
		LifeSteal = {
			Slot = "Skill3",
			Range = 30,
			Radius = 20,
			Duration = 8,
			NormalMaxTargets = 3,
			UltimateMaxTargets = 10,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Demon Prince",
			RequiresFullEnergy = true,
			Duration = 20,
			DamageBonus = 0.35,
			PulseCount = 10,
			PulseRadius = 33.3,
			InitialOrbs = 3,
		},
		Dodge = {
			Slot = "Dodge",
			HasBackstep = true,
			HasBlinkDash = true,
		},
	}

	function Demon.Describe()
		return METADATA
	end

	function Demon.IsDemonPrince()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local ultimateMode = properties and properties:FindFirstChild("UltimateMode")

		return ultimateMode ~= nil and ultimateMode.Value == true
	end

	function Demon.GetOrbCount()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local orbs = properties and properties:FindFirstChild("UltOrbs")

		return orbs and #orbs:GetChildren() or 0
	end

	function Demon.GetEnergyState()
		return Energy.GetState()
	end

	function Demon.GetHealthState()
		return Health.GetState()
	end

	function Demon.IsUltimateReady()
		if Demon.IsDemonPrince() then
			return false, "demon_prince_active"
		end

		return Energy.IsFull()
	end

	function Demon.IsDarkBindingSafe(minimumHealthPercent)
		local healthState, healthError = Health.GetState()

		if not healthState then
			return false, healthError
		end

		local minimum = math.clamp(
			(tonumber(minimumHealthPercent) or 50) / 100,
			METADATA.DarkBinding.HealthCost,
			1
		)

		if healthState.Ratio < minimum then
			return false, "health_below_dark_binding_limit"
		end

		return true
	end

	function Demon.EnsureUnsheathed()
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

	function Demon.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Demon.IsUltimateReady()
		end

		return true
	end

	function Demon.Use(slot)
		local canUse, reason = Demon.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Demon.UsePrimary()
		return Demon.Use(METADATA.Primary.Slot)
	end

	function Demon.UseDarkBinding(minimumHealthPercent)
		local safe, safeError = Demon.IsDarkBindingSafe(minimumHealthPercent)

		if not safe then
			return nil, safeError
		end

		return Demon.Use(METADATA.DarkBinding.Slot)
	end

	function Demon.UseScytheThrow()
		return Demon.Use(METADATA.ScytheThrow.Slot)
	end

	function Demon.UseLifeSteal()
		return Demon.Use(METADATA.LifeSteal.Slot)
	end

	function Demon.UseUltimate()
		return Demon.Use(METADATA.Ultimate.Slot)
	end

	function Demon.UseDodge()
		return Demon.Use(METADATA.Dodge.Slot)
	end

	return Demon
end
