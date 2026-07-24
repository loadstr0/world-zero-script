return function(ctx)
	local Necromancer = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "Necromancer",
		AutomationRange = 30,
		Primary = {
			Slot = "Primary",
			Name = "Deadly Gash",
			ComboSteps = 9,
			ComboReset = 1,
			ConeRange = 14,
			ConeAngle = 25,
		},
		TombstoneRise = {
			Slot = "Skill1",
			Cooldown = 5,
			PulseCount = 5,
			CenterOffset = 15,
			Width = 22,
			Depth = 26,
		},
		SpiritBurst = {
			Slot = "Skill2",
			Cooldown = 3,
			SoulsPerCharge = 3,
			MaximumCharges = 4,
			MaximumStoredSouls = 12,
			ChargeRadii = {
				[0] = 13,
				[1] = 14,
				[2] = 16,
				[3] = 18,
				[4] = 21,
			},
		},
		SpiritCavern = {
			Slot = "Skill3",
			Cooldown = 10,
			PulseCount = 6,
			PulseInterval = 1.1,
			CenterOffset = 8,
			Radius = 20,
			AppliesHexed = true,
			AttackReduction = 0.35,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Undead Army",
			Cooldown = 30,
			RequiresFullEnergy = true,
			SummonCount = 10,
			ImpactRadius = 30,
			SummonsInflictFear = true,
			ImpactAppliesHexed = true,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function Necromancer.Describe()
		return METADATA
	end

	function Necromancer.GetSoulState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local souls = properties and properties:FindFirstChild("Souls")
		local raw = souls and tonumber(souls.Value) or 0
		local chargeCount = math.min(
			math.floor(raw / METADATA.SpiritBurst.SoulsPerCharge),
			METADATA.SpiritBurst.MaximumCharges
		)
		local remainder = raw % METADATA.SpiritBurst.SoulsPerCharge

		return {
			Raw = raw,
			Charges = chargeCount,
			MaximumCharges = METADATA.SpiritBurst.MaximumCharges,
			Remainder = remainder,
			SoulsPerCharge = METADATA.SpiritBurst.SoulsPerCharge,
			AtMaximumCharge = chargeCount >= METADATA.SpiritBurst.MaximumCharges,
			BurstRadius = METADATA.SpiritBurst.ChargeRadii[chargeCount],
		}
	end

	function Necromancer.GetEnergyState()
		return Energy.GetState()
	end

	function Necromancer.IsUltimateReady()
		return Energy.IsFull()
	end

	function Necromancer.GetTargetDistance(target)
		local root = GameContext.GetRootPart()

		if not root or not target then
			return nil
		end

		local targetPart = target.PrimaryPart
			or target:FindFirstChild("Collider")
			or target:FindFirstChild("HumanoidRootPart")

		if not targetPart then
			return nil
		end

		return (root.Position - targetPart.Position).Magnitude
	end

	function Necromancer.EnsureUnsheathed()
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

	function Necromancer.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Necromancer.IsUltimateReady()
		end

		return true
	end

	function Necromancer.CanUseSpiritBurst(minimumCharges)
		local canUse, useError = Necromancer.CanUse(METADATA.SpiritBurst.Slot)

		if not canUse then
			return false, useError
		end

		local required = math.clamp(
			tonumber(minimumCharges) or 0,
			0,
			METADATA.SpiritBurst.MaximumCharges
		)

		if Necromancer.GetSoulState().Charges < required then
			return false, "not_enough_soul_charges"
		end

		return true
	end

	function Necromancer.Use(slot)
		local canUse, reason = Necromancer.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Necromancer.UsePrimary()
		return Necromancer.Use(METADATA.Primary.Slot)
	end

	function Necromancer.UseTombstoneRise()
		return Necromancer.Use(METADATA.TombstoneRise.Slot)
	end

	function Necromancer.UseSpiritBurst(minimumCharges)
		local canUse, reason = Necromancer.CanUseSpiritBurst(minimumCharges)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.SpiritBurst.Slot)
	end

	function Necromancer.UseSpiritCavern()
		return Necromancer.Use(METADATA.SpiritCavern.Slot)
	end

	function Necromancer.UseUltimate()
		return Necromancer.Use(METADATA.Ultimate.Slot)
	end

	function Necromancer.UseDodge()
		return Necromancer.Use(METADATA.Dodge.Slot)
	end

	return Necromancer
end
