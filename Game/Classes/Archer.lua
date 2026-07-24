return function(ctx)
	local Archer = {}

	local Actions = ctx:Require("Actions")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "Archer",
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 60,
		},
		PiercingArrow = {
			Slot = "Skill1",
			Range = 60,
			Chains = true,
		},
		SpiritBomb = {
			Slot = "Skill2",
			Range = 60,
			Radius = 18,
			SlowDuration = 4,
		},
		MortarStrike = {
			Slot = "Skill3",
			Range = 60,
			Radius = 18,
			HitCount = 8,
			Duration = 3,
		},
		Ultimate = {
			Slot = "Ultimate",
			RequiredGreatSpiritArrows = 6,
		},
		Dodge = {
			Slot = "Dodge",
			HasBackstepAttack = true,
		},
	}

	function Archer.Describe()
		return METADATA
	end

	function Archer.IsSheathed()
		return Actions.IsSheathed()
	end

	function Archer.EnsureUnsheathed()
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

	function Archer.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		return true
	end

	function Archer.GetResourceState()
		local character = GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local properties = character:FindFirstChild("Properties")

		if not properties then
			return nil, "character_properties_unavailable"
		end

		local energy = properties:FindFirstChild("Energy")
		local arrowCount = properties:FindFirstChild("BackSwordCount")

		if not energy or not arrowCount then
			return nil, "archer_resource_values_unavailable"
		end

		return {
			Energy = tonumber(energy.Value) or 0,
			GreatSpiritArrows = tonumber(arrowCount.Value) or 0,
			UltimateReady = (tonumber(arrowCount.Value) or 0)
				>= METADATA.Ultimate.RequiredGreatSpiritArrows,
		}
	end

	function Archer.IsUltimateReady()
		local resourceState, resourceError = Archer.GetResourceState()

		if not resourceState then
			return false, resourceError
		end

		return resourceState.UltimateReady
	end

	function Archer.Use(slot)
		local canUse, reason = Archer.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Archer.UsePrimary()
		return Archer.Use(METADATA.Primary.Slot)
	end

	function Archer.UsePiercingArrow()
		return Archer.Use(METADATA.PiercingArrow.Slot)
	end

	function Archer.UseSpiritBomb()
		return Archer.Use(METADATA.SpiritBomb.Slot)
	end

	function Archer.UseMortarStrike()
		return Archer.Use(METADATA.MortarStrike.Slot)
	end

	function Archer.UseUltimate()
		local ultimateReady, resourceError = Archer.IsUltimateReady()

		if not ultimateReady then
			return nil, resourceError or "ultimate_not_ready"
		end

		return Archer.Use(METADATA.Ultimate.Slot)
	end

	function Archer.UseDodge()
		return Archer.Use(METADATA.Dodge.Slot)
	end

	return Archer
end
