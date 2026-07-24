return function(ctx)
	local Berserker = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "Berserker",
		AutomationRange = 20,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 16,
			ConeAngle = 45,
			ComboSteps = 6,
			ComboReset = 1,
		},
		AggroSlam = {
			Slot = "Skill1",
			Radius = 16,
			AggroRadius = 65,
		},
		GigaSpin = {
			Slot = "Skill2",
			Radius = 15,
			HitCount = 8,
		},
		Fissure = {
			Slot = "Skill3",
			BaseHitCount = 2,
			RageEruption = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Rage",
			RequiresFullEnergy = true,
			Duration = 15,
			DefenseBonus = 0.7,
			PrimaryDamageBonus = 0.25,
		},
		Dodge = {
			Slot = "Dodge",
		},
		SwapPerk = {
			Slot = "SwapPerk",
		},
	}

	function Berserker.Describe()
		return METADATA
	end

	function Berserker.IsRaging()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local rage = properties and properties:FindFirstChild("Berserk")

		return rage ~= nil and rage.Value == true
	end

	function Berserker.GetEnergyState()
		return Energy.GetState()
	end

	function Berserker.IsUltimateReady()
		if Berserker.IsRaging() then
			return false, "rage_already_active"
		end

		return Energy.IsFull()
	end

	function Berserker.EnsureUnsheathed()
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

	function Berserker.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Berserker.IsUltimateReady()
		end

		return true
	end

	function Berserker.Use(slot)
		local canUse, reason = Berserker.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Berserker.UsePrimary()
		return Berserker.Use(METADATA.Primary.Slot)
	end

	function Berserker.UseAggroSlam()
		return Berserker.Use(METADATA.AggroSlam.Slot)
	end

	function Berserker.UseGigaSpin()
		return Berserker.Use(METADATA.GigaSpin.Slot)
	end

	function Berserker.UseFissure()
		return Berserker.Use(METADATA.Fissure.Slot)
	end

	function Berserker.UseUltimate()
		return Berserker.Use(METADATA.Ultimate.Slot)
	end

	function Berserker.UseDodge()
		return Berserker.Use(METADATA.Dodge.Slot)
	end

	function Berserker.SwapPerk()
		return Berserker.Use(METADATA.SwapPerk.Slot)
	end

	return Berserker
end
