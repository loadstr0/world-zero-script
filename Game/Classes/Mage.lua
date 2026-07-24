return function(ctx)
	local Mage = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "Mage",
		AutomationRange = 45,
		Primary = {
			Slot = "Primary",
			Name = "Arcane Orbs",
			Range = 45,
			ComboSteps = 3,
			ComboReset = 1,
			RequiresLineOfSight = true,
			AllowsMovement = true,
		},
		ArcaneBlast = {
			Slot = "Skill1",
			Range = 45,
			ExplosionRadius = 15,
			DamageEvents = 2,
		},
		ArcaneWave = {
			Slot = "Skill2",
			VisualBurstCount = 4,
			MaximumDamageCallbacks = 12,
			TravelsForward = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Arcane Ascension",
			RequiresFullEnergy = true,
			TargetRange = 60,
			CastDelay = 2,
			ExplosionRadius = 20,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function Mage.Describe()
		return METADATA
	end

	function Mage.GetEnergyState()
		return Energy.GetState()
	end

	function Mage.IsUltimateReady()
		return Energy.IsFull()
	end

	function Mage.GetTargetDistance(target)
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

	function Mage.EnsureUnsheathed()
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

	function Mage.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Mage.IsUltimateReady()
		end

		return true
	end

	function Mage.Use(slot)
		local canUse, reason = Mage.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Mage.UsePrimary()
		return Mage.Use(METADATA.Primary.Slot)
	end

	function Mage.UseArcaneBlast()
		return Mage.Use(METADATA.ArcaneBlast.Slot)
	end

	function Mage.UseArcaneWave()
		return Mage.Use(METADATA.ArcaneWave.Slot)
	end

	function Mage.UseUltimate()
		return Mage.Use(METADATA.Ultimate.Slot)
	end

	function Mage.UseDodge()
		return Mage.Use(METADATA.Dodge.Slot)
	end

	return Mage
end
