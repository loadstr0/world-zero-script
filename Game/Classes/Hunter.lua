return function(ctx)
	local Hunter = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")
	local Profile = ctx:Require("Profile")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Hunter",
		AutomationRange = 60,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 60,
			RequiresLineOfSight = true,
		},
		BlazingShot = {
			Slot = "Skill1",
			FunctionName = "HuntersMark",
			Range = 60,
			GroundPulseCount = 4,
			GroundPulseDelay = 0.5,
			GroundPulseInterval = 1,
			GroundPulseRadius = 28,
			InflictsBurn = true,
		},
		Familiar = {
			Slot = "Skill2",
			TameRange = 15,
			TameWindow = 10,
			TargetRadius = 40,
			HealthMultiplier = 10,
			BaseAttackRatio = 0.1,
			FrenzyDuration = 8,
			FrenzyAttackRatio = 0.15,
			FrenzyCriticalBonus = 0.3,
		},
		VenomTrap = {
			Slot = "Skill3",
			PlacementDistance = 6,
			CaptureRadius = 4,
			MaximumTargets = 25,
			StopDuration = 4,
			InflictsVenom = true,
			PullsNonBossTargets = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Divine Arrow",
			RequiresFullEnergy = true,
			TargetRange = 60,
			PulseCount = 10,
			PulseInterval = 1,
			DamageAndHealRadius = 50,
			FamiliarDefenseBonus = 0.8,
		},
		Dodge = {
			Slot = "Dodge",
			Name = "Trick Shot",
			StandingStillShootsArrow = true,
			CriticalMultiplier = 3,
			SlowRatio = 0.65,
		},
	}

	function Hunter.Describe()
		return METADATA
	end

	function Hunter.GetFamiliarState()
		local familiarName, profileError = Profile.GetValue("HunterFamiliar")
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local familiarValue = properties and properties:FindFirstChild("Familiar")
		local familiar = familiarValue and familiarValue.Value or nil
		local healthState, healthError

		if familiar then
			healthState, healthError = Health.GetState(familiar)
		end

		return {
			Name = type(familiarName) == "string" and familiarName or "",
			Tamed = type(familiarName) == "string" and familiarName ~= "",
			Active = familiar ~= nil,
			Instance = familiar,
			Frenzy = familiar ~= nil and Status.Has("FrenzyMode", familiar) or false,
			Health = healthState,
			HealthError = healthError or profileError,
		}
	end

	function Hunter.GetPlayerHealthState()
		return Health.GetState()
	end

	function Hunter.GetEnergyState()
		return Energy.GetState()
	end

	function Hunter.IsUltimateReady()
		return Energy.IsFull()
	end

	function Hunter.GetTargetDistance(target)
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

	function Hunter.EnsureUnsheathed()
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

	function Hunter.CanUseFamiliar()
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		for _, slot in ipairs({ "Skill2", "Summon", "Frenzy" }) do
			if Actions.IsOnCooldown(slot) == true then
				return false, "cooldown:" .. slot
			end
		end

		return true
	end

	function Hunter.CanUse(slot)
		if slot == METADATA.Familiar.Slot then
			return Hunter.CanUseFamiliar()
		end

		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Hunter.IsUltimateReady()
		end

		return true
	end

	function Hunter.Use(slot)
		local canUse, reason = Hunter.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Hunter.UsePrimary()
		return Hunter.Use(METADATA.Primary.Slot)
	end

	function Hunter.UseBlazingShot()
		return Hunter.Use(METADATA.BlazingShot.Slot)
	end

	function Hunter.UseFamiliar()
		return Hunter.Use(METADATA.Familiar.Slot)
	end

	function Hunter.UseVenomTrap()
		return Hunter.Use(METADATA.VenomTrap.Slot)
	end

	function Hunter.UseUltimate()
		return Hunter.Use(METADATA.Ultimate.Slot)
	end

	function Hunter.UseDodge()
		return Hunter.Use(METADATA.Dodge.Slot)
	end

	return Hunter
end
