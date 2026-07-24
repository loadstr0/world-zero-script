return function(ctx)
	local DualWielder = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")

	local SPEED_MULTIPLIERS = {
		[0] = 1,
		[1] = 1.05,
		[2] = 1.1,
		[3] = 1.15,
		[4] = 1.2,
		[5] = 1.25,
		[6] = 1.3,
		[7] = 1.35,
		[8] = 1.4,
		[9] = 1.45,
		[10] = 1.5,
	}

	local METADATA = {
		ClassName = "DualWielder",
		AutomationRange = 20,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 8,
			ComboReset = 0.75,
			MaximumSpeedStacks = 10,
			MaximumSpeedMultiplier = 1.5,
			SpeedStackTimeout = 3,
		},
		AttackBuff = {
			Slot = "Skill1",
			Name = "Tempo",
			Duration = 6,
			MaximumSpeedStacks = 10,
			KillExtension = 4,
			KillHealRatio = 0.05,
		},
		LeapStrikes = {
			Slot = "Skill2",
			Range = 14,
			ConeAngle = 45,
		},
		CrossSlash = {
			Slot = "Skill3",
			CrescentCount = 2,
		},
		Ultimate = {
			Slot = "Ultimate",
			RequiresFullEnergy = true,
			ConeHits = 9,
			FallingSwords = 16,
			SlamHits = 4,
			MaximumAttackEvents = 29,
			SlamRadius = 15,
			ShockwaveRadius = 10,
		},
		Dodge = {
			Slot = "Dodge",
		},
		SwapPerk = {
			Slot = "SwapPerk",
		},
	}

	function DualWielder.Describe()
		return METADATA
	end

	function DualWielder.GetSpeedState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local attackSpeed = properties and properties:FindFirstChild("AttackSpeed")
		local stacks = attackSpeed and tonumber(attackSpeed.Value) or 0

		stacks = math.clamp(math.floor(stacks), 0, METADATA.Primary.MaximumSpeedStacks)

		return {
			Stacks = stacks,
			MaximumStacks = METADATA.Primary.MaximumSpeedStacks,
			Multiplier = SPEED_MULTIPLIERS[stacks] or 1,
			Tempo = Status.Has("DualWielderTempo"),
		}
	end

	function DualWielder.IsTempoActive()
		return Status.Has("DualWielderTempo")
	end

	function DualWielder.GetEnergyState()
		return Energy.GetState()
	end

	function DualWielder.IsUltimateReady()
		return Energy.IsFull()
	end

	function DualWielder.EnsureUnsheathed()
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

	function DualWielder.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return DualWielder.IsUltimateReady()
		end

		return true
	end

	function DualWielder.Use(slot)
		local canUse, reason = DualWielder.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function DualWielder.UsePrimary()
		return DualWielder.Use(METADATA.Primary.Slot)
	end

	function DualWielder.UseAttackBuff()
		return DualWielder.Use(METADATA.AttackBuff.Slot)
	end

	function DualWielder.UseLeapStrikes()
		return DualWielder.Use(METADATA.LeapStrikes.Slot)
	end

	function DualWielder.UseCrossSlash()
		return DualWielder.Use(METADATA.CrossSlash.Slot)
	end

	function DualWielder.UseUltimate()
		return DualWielder.Use(METADATA.Ultimate.Slot)
	end

	function DualWielder.UseDodge()
		return DualWielder.Use(METADATA.Dodge.Slot)
	end

	function DualWielder.SwapPerk()
		return DualWielder.Use(METADATA.SwapPerk.Slot)
	end

	return DualWielder
end
