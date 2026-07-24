return function(ctx)
	local MageOfShadows = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "MageOfShadows",
		AutomationRange = 45,
		Primary = {
			Slot = "Primary",
			Name = "Shadow Seeker",
			Range = 45,
			ExplosionRadius = 15,
			RequiresLineOfSight = true,
			MaximumOrbs = 10,
			NormalOrbRate = 1,
			ShadowFormOrbRate = 2,
		},
		ShadowExplosion = {
			Slot = "Skill1",
			Name = "Shadow Explosion",
			Cooldown = 10,
			CastDelay = 0.6,
		},
		ShadowMerge = {
			Slot = "Skill2",
			Name = "Shadow Merge",
			Cooldown = 3,
			SmallOrbsPerLargeOrb = 3,
			MaximumLargeOrbs = 3,
			LargeOrbTargetRange = 30,
			LargeOrbLifetime = 24.5,
		},
		ShadowChains = {
			Slot = "Skill3",
			Name = "Shadow Chains",
			Cooldown = 15,
			SearchRadius = 40,
			MaximumTargets = 5,
			DamagePulses = 6,
			SlowDuration = 6,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Shadow Form",
			Cooldown = 30,
			RequiresFullEnergy = true,
			Duration = 10,
			CooldownReduction = 0.7,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function MageOfShadows.Describe()
		return METADATA
	end

	function MageOfShadows.GetOrbState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local shadowOrbs = properties and properties:FindFirstChild("ShadowOrbs")
		local children = shadowOrbs and shadowOrbs:GetChildren() or {}
		local special = 0

		for _, orb in ipairs(children) do
			if orb:IsA("BoolValue") and orb.Value == true then
				special = special + 1
			end
		end

		return {
			Total = #children,
			Maximum = METADATA.Primary.MaximumOrbs,
			Special = special,
			MergeGroups = math.floor(#children / METADATA.ShadowMerge.SmallOrbsPerLargeOrb),
		}
	end

	function MageOfShadows.IsShadowFormActive()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local shadowForm = properties and properties:FindFirstChild("ShadowFormActive")

		return shadowForm ~= nil and shadowForm.Value == true
	end

	function MageOfShadows.HasFastCooldown()
		return Status.Has("FastCooldown")
	end

	function MageOfShadows.GetEnergyState()
		return Energy.GetState()
	end

	function MageOfShadows.IsUltimateReady()
		return Energy.IsFull()
	end

	function MageOfShadows.GetTargetDistance(target)
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

	function MageOfShadows.EnsureUnsheathed()
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

	function MageOfShadows.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Primary.Slot and MageOfShadows.GetOrbState().Total == 0 then
			return false, "no_shadow_orbs"
		end

		if slot == METADATA.Ultimate.Slot then
			return MageOfShadows.IsUltimateReady()
		end

		return true
	end

	function MageOfShadows.CanMerge(minimumSmallOrbs)
		local canUse, useError = MageOfShadows.CanUse(METADATA.ShadowMerge.Slot)

		if not canUse then
			return false, useError
		end

		local required = math.max(
			METADATA.ShadowMerge.SmallOrbsPerLargeOrb,
			tonumber(minimumSmallOrbs) or METADATA.ShadowMerge.SmallOrbsPerLargeOrb
		)

		if MageOfShadows.GetOrbState().Total < required then
			return false, "not_enough_shadow_orbs"
		end

		return true
	end

	function MageOfShadows.Use(slot)
		local canUse, reason = MageOfShadows.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function MageOfShadows.UsePrimary()
		return MageOfShadows.Use(METADATA.Primary.Slot)
	end

	function MageOfShadows.UseShadowExplosion()
		return MageOfShadows.Use(METADATA.ShadowExplosion.Slot)
	end

	function MageOfShadows.UseShadowMerge(minimumSmallOrbs)
		local canMerge, reason = MageOfShadows.CanMerge(minimumSmallOrbs)

		if not canMerge then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.ShadowMerge.Slot)
	end

	function MageOfShadows.UseShadowChains()
		return MageOfShadows.Use(METADATA.ShadowChains.Slot)
	end

	function MageOfShadows.UseUltimate()
		return MageOfShadows.Use(METADATA.Ultimate.Slot)
	end

	function MageOfShadows.UseDodge()
		return MageOfShadows.Use(METADATA.Dodge.Slot)
	end

	return MageOfShadows
end
