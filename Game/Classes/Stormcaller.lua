return function(ctx)
	local Stormcaller = {}
	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Stormcaller",
		AutomationRange = 50,
		Primary = { Slot = "Primary", Name = "Shock Bolts", Range = 50, ComboSteps = 3, RequiresLineOfSight = true },
		Supercharge = {
			Slot = "Skill1", Cooldown = 7, Duration = 6.9,
			HealthCostRatio = 0.2, MarkDuration = 5,
			HealPerApplication = 0.005, VerifiedRefundCap = 0.15,
			CannotKillCaster = true,
		},
		ChainLightning = {
			Slot = "Skill2", Cooldown = 7, InitialRange = 35,
			MaximumTargets = 8, CanReturnToPreviousTargets = true,
		},
		StormSurge = {
			Slot = "Skill3", Cooldown = 10, TargetRange = 45,
			DamageEvents = 2, AppliesSlowdown = true,
			ThunderGodSpeedMultiplier = 1.5,
		},
		Ultimate = {
			Slot = "Ultimate", Name = "Thunder God", Cooldown = 30,
			RequiresFullEnergy = true, Duration = 20,
			MovementMultiplier = 1.5, PrimaryRange = 14,
			PrimaryConeAngle = 25, PrimaryAnimationSpeed = 1.35,
			DischargeChance = 0.25, DischargeRange = 35,
			DischargeGate = 1.5,
		},
		Dodge = {
			Slot = "Dodge", Name = "Discharge Dash",
			ForwardDamageEvents = 3, BackstepDamageEvents = 1,
		},
	}

	local function getProperty(name)
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		return properties and properties:FindFirstChild(name)
	end

	local function readBoolProperty(name)
		local property = getProperty(name)
		return property ~= nil and property.Value == true
	end

	function Stormcaller.Describe()
		return METADATA
	end

	function Stormcaller.GetHealthState()
		return Health.GetState()
	end

	function Stormcaller.GetEnergyState()
		return Energy.GetState()
	end

	function Stormcaller.GetState()
		return {
			Supercharged = readBoolProperty("Supercharged"),
			ThunderGod = readBoolProperty("ThunderGod"),
			UltimateSpeed = Status.Has("StormcallerUltimateSpeed"),
		}
	end

	function Stormcaller.GetProjectedSuperchargeState()
		local health, healthError = Stormcaller.GetHealthState()

		if not health then
			return nil, healthError
		end

		local requestedCost = health.Maximum * METADATA.Supercharge.HealthCostRatio
		local actualCost = math.min(requestedCost, math.max(health.Current - 1, 0))
		local projectedCurrent = health.Current - actualCost

		return {
			Current = health.Current,
			Maximum = health.Maximum,
			CurrentRatio = health.Ratio,
			ProjectedCurrent = projectedCurrent,
			ProjectedRatio = math.clamp(projectedCurrent / health.Maximum, 0, 1),
			ActualCost = actualCost,
		}
	end

	function Stormcaller.GetTargetDistance(target)
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

	function Stormcaller.IsUltimateReady()
		return Energy.IsFull()
	end

	function Stormcaller.EnsureUnsheathed()
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

	function Stormcaller.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Stormcaller.IsUltimateReady()
		end

		return true
	end

	function Stormcaller.CanSupercharge(remainingHealthFloor)
		local canUse, useError = Stormcaller.CanUse(METADATA.Supercharge.Slot)

		if not canUse then
			return false, useError
		end

		if Stormcaller.GetState().Supercharged then
			return false, "already_supercharged"
		end

		local projected, projectedError = Stormcaller.GetProjectedSuperchargeState()

		if not projected then
			return false, projectedError
		end

		if projected.ProjectedRatio < (remainingHealthFloor or 0) then
			return false, "projected_health_below_floor"
		end

		return true
	end

	function Stormcaller.Use(slot)
		local canUse, reason = Stormcaller.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Stormcaller.UsePrimary()
		return Stormcaller.Use(METADATA.Primary.Slot)
	end

	function Stormcaller.UseSupercharge(remainingHealthFloor)
		local canUse, reason = Stormcaller.CanSupercharge(remainingHealthFloor or 0)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.Supercharge.Slot)
	end

	function Stormcaller.UseChainLightning()
		return Stormcaller.Use(METADATA.ChainLightning.Slot)
	end

	function Stormcaller.UseStormSurge()
		return Stormcaller.Use(METADATA.StormSurge.Slot)
	end

	function Stormcaller.UseUltimate()
		return Stormcaller.Use(METADATA.Ultimate.Slot)
	end

	function Stormcaller.UseDodge()
		return Stormcaller.Use(METADATA.Dodge.Slot)
	end

	return Stormcaller
end
