return function(ctx)
	local Swordmaster = {}

	local Actions = ctx:Require("Actions")

	local METADATA = {
		ClassName = "Swordmaster",
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			ComboSteps = 6,
			ComboReset = 0.75,
			Range = 10,
		},
		CrescentStrike = {
			Slot = "Skill1",
			Range = 50,
		},
		LeapSlash = {
			Slot = "Skill2",
		},
		Dodge = {
			Slot = "Dodge",
		},
		Ultimate = {
			Slot = "Ultimate",
			Range = 30,
			HitCount = 20,
			RequiresFullEnergy = true,
		},
	}

	function Swordmaster.Describe()
		return METADATA
	end

	function Swordmaster.IsSheathed()
		return Actions.IsSheathed()
	end

	function Swordmaster.EnsureUnsheathed()
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

	function Swordmaster.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		return true
	end

	function Swordmaster.Use(slot)
		local canUse, reason = Swordmaster.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Swordmaster.UsePrimary()
		return Swordmaster.Use(METADATA.Primary.Slot)
	end

	function Swordmaster.UseCrescentStrike()
		return Swordmaster.Use(METADATA.CrescentStrike.Slot)
	end

	function Swordmaster.UseLeapSlash()
		return Swordmaster.Use(METADATA.LeapSlash.Slot)
	end

	function Swordmaster.UseDodge()
		return Swordmaster.Use(METADATA.Dodge.Slot)
	end

	function Swordmaster.UseUltimate()
		return Swordmaster.Use(METADATA.Ultimate.Slot)
	end

	return Swordmaster
end
