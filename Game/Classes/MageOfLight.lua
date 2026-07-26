return function(ctx)
	local MageOfLight = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "MageOfLight",
		AutomationRange = 45,
		Primary = {
			Slot = "Primary",
			Name = "Light Seeker",
			Range = 45,
			RequiresLineOfSight = true,
			ClientLineOfSightBypass = true,
			ExplosionRadius = 15,
			MaximumOrbs = 10,
		},
		HealingCircle = {
			Slot = "Skill1",
			Radius = 22.5,
			PulseCount = 6,
			PulseInterval = 1,
			HealingStatusDuration = 3,
		},
		InfusedLight = {
			Slot = "Skill2",
			HealthCostPerNormalOrb = 0.04,
			MinimumHealthCost = 0.04,
			MaximumHealthCost = 0.4,
		},
		Barrier = {
			Slot = "Skill3",
			EffectRadius = 40,
			ScalesWithHealth = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Grace",
			RequiresFullEnergy = true,
			Radius = 30,
			ChargedOrbs = 10,
			BlessedDuration = 10,
			HealAndBarrierPulseCount = 10,
			HealAndBarrierPulseInterval = 0.5,
			CleansesStatuses = true,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function MageOfLight.Describe()
		return METADATA
	end

	function MageOfLight.GetOrbState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local orbs = properties and properties:FindFirstChild("Orbs")
		local children = orbs and orbs:GetChildren() or {}
		local charged = 0

		for _, orb in ipairs(children) do
			if orb.Value == true then
				charged = charged + 1
			end
		end

		local normal = #children - charged

		return {
			Total = #children,
			Maximum = METADATA.Primary.MaximumOrbs,
			Normal = normal,
			Charged = charged,
			InfuseCostRatio = normal
				* METADATA.InfusedLight.HealthCostPerNormalOrb,
		}
	end

	function MageOfLight.IsWingsActive()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local wingsActive = properties and properties:FindFirstChild("WingsActive")

		return wingsActive ~= nil and wingsActive.Value == true
	end

	function MageOfLight.IsBlessed()
		return Status.Has("Blessed")
	end

	function MageOfLight.GetHealthState()
		return Health.GetState()
	end

	function MageOfLight.GetBarrier()
		return Health.GetBarrier()
	end

	function MageOfLight.GetEnergyState()
		return Energy.GetState()
	end

	function MageOfLight.IsUltimateReady()
		return Energy.IsFull()
	end

	function MageOfLight.EnsureUnsheathed()
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

	function MageOfLight.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Primary.Slot and MageOfLight.GetOrbState().Total == 0 then
			return false, "no_orbs"
		end

		if slot == METADATA.Ultimate.Slot then
			return MageOfLight.IsUltimateReady()
		end

		return true
	end

	function MageOfLight.CanInfuse(minimumNormalOrbs, remainingHealthFloor)
		local canUse, useError = MageOfLight.CanUse(METADATA.InfusedLight.Slot)

		if not canUse then
			return false, useError
		end

		local orbs = MageOfLight.GetOrbState()

		if orbs.Normal < minimumNormalOrbs then
			return false, "not_enough_normal_orbs"
		end

		local health, healthError = MageOfLight.GetHealthState()

		if not health then
			return false, healthError
		end

		if health.Ratio - orbs.InfuseCostRatio < remainingHealthFloor then
			return false, "projected_health_below_floor"
		end

		return true
	end

	function MageOfLight.Use(slot)
		local canUse, reason = MageOfLight.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		if
			slot == METADATA.Primary.Slot
			and METADATA.Primary.ClientLineOfSightBypass
		then
			return Actions.UseSkillWithLineOfSightBypass(slot)
		end

		return Actions.UseSkill(slot)
	end

	function MageOfLight.UsePrimary()
		return MageOfLight.Use(METADATA.Primary.Slot)
	end

	function MageOfLight.UseHealingCircle()
		return MageOfLight.Use(METADATA.HealingCircle.Slot)
	end

	function MageOfLight.UseInfusedLight(minimumNormalOrbs, remainingHealthFloor)
		local canInfuse, reason =
			MageOfLight.CanInfuse(minimumNormalOrbs or 1, remainingHealthFloor or 0)

		if not canInfuse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.InfusedLight.Slot)
	end

	function MageOfLight.UseBarrier()
		return MageOfLight.Use(METADATA.Barrier.Slot)
	end

	function MageOfLight.UseUltimate()
		return MageOfLight.Use(METADATA.Ultimate.Slot)
	end

	function MageOfLight.UseDodge()
		return MageOfLight.Use(METADATA.Dodge.Slot)
	end

	return MageOfLight
end
