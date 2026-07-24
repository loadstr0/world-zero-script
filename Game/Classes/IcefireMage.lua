return function(ctx)
	local IcefireMage = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "IcefireMage",
		AutomationRange = 45,
		Primary = {
			Slot = "Primary",
			Name = "Ice Needle",
			FunctionName = "Attack",
			Range = 50,
			ComboSteps = 3,
			ComboReset = 1,
			RequiresLineOfSight = true,
			InflictsFrost = true,
		},
		IcicleField = {
			Slot = "Skill1",
			FunctionName = "IcySpikes",
			SemiCircleRange = 20,
			InflictsSuperFrost = true,
		},
		Fireball = {
			Slot = "Skill2",
			Range = 45,
			ExplosionRadius = 15,
			DamageEvents = 2,
			InflictsBurn = true,
		},
		LightningStrike = {
			Slot = "Skill3",
			AimRange = 45,
			StrikeDistance = 12,
			InflictsShock = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Meteor Crash",
			RequiresFullEnergy = true,
			CenterDistance = 10,
			OpeningFrostRadius = 20,
			SmallMeteorCount = 9,
			SmallMeteorRadius = 14,
			FinalMeteorRadius = 20,
			MaximumDamageEvents = 11,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function IcefireMage.Describe()
		return METADATA
	end

	function IcefireMage.GetEnergyState()
		return Energy.GetState()
	end

	function IcefireMage.IsUltimateReady()
		return Energy.IsFull()
	end

	function IcefireMage.GetTargetDistance(target)
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

	function IcefireMage.EnsureUnsheathed()
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

	function IcefireMage.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return IcefireMage.IsUltimateReady()
		end

		return true
	end

	function IcefireMage.Use(slot)
		local canUse, reason = IcefireMage.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function IcefireMage.UsePrimary()
		return IcefireMage.Use(METADATA.Primary.Slot)
	end

	function IcefireMage.UseIcicleField()
		return IcefireMage.Use(METADATA.IcicleField.Slot)
	end

	function IcefireMage.UseFireball()
		return IcefireMage.Use(METADATA.Fireball.Slot)
	end

	function IcefireMage.UseLightningStrike()
		return IcefireMage.Use(METADATA.LightningStrike.Slot)
	end

	function IcefireMage.UseUltimate()
		return IcefireMage.Use(METADATA.Ultimate.Slot)
	end

	function IcefireMage.UseDodge()
		return IcefireMage.Use(METADATA.Dodge.Slot)
	end

	return IcefireMage
end
