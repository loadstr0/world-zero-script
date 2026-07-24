return function(ctx)
	local Summoner = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local MobsAPI = ctx:Require("MobsAPI")

	local METADATA = {
		ClassName = "Summoner",
		AutomationRange = 70,
		Primary = {
			Slot = "Primary",
			Name = "Rift Rifle",
			Range = 70,
			ComboSteps = 4,
			ComboReset = 1,
			RequiresLineOfSight = true,
			SoulChance = 0.25,
			SoulsPerProc = 40,
			ServerReplicationInterval = 0.2,
		},
		Summon = {
			Slot = "Skill1",
			Cooldown = 5,
			SoulsPerCharge = 100,
			MaximumReadyCount = 5,
			SpawnsAllReady = true,
		},
		RiftExplosion = {
			Slot = "Skill2",
			Cooldown = 3,
			OnlyDetonatesLesserSummons = true,
		},
		SoulHarvest = {
			Slot = "Skill3",
			Cooldown = 10,
			TargetRange = 40,
			Radius = 20,
			InitialDamageEvents = 1,
			PulseCount = 4,
			MaximumTargetsPerPulse = 6,
			SoulsPerTargetPerPulse = 15,
			MaximumHarvestedSouls = 300,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Super Summon",
			Cooldown = 30,
			RequiresFullEnergy = true,
			SummonType = "Greater Soul Being",
			BonusLevels = 10,
		},
		KillSouls = {
			MinimumOrbs = 1,
			MaximumOrbs = 3,
			SoulsPerOrb = 20,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	function Summoner.Describe()
		return METADATA
	end

	function Summoner.GetSoulState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local souls = properties and properties:FindFirstChild("Souls")
		local summonCount = properties and properties:FindFirstChild("SummonCount")
		local rawSouls = souls and tonumber(souls.Value) or 0
		local readyCount = summonCount and tonumber(summonCount.Value) or 0

		return {
			Souls = rawSouls,
			SoulsPerCharge = METADATA.Summon.SoulsPerCharge,
			ProgressRatio = math.clamp(
				rawSouls / METADATA.Summon.SoulsPerCharge,
				0,
				1
			),
			ReadyCount = readyCount,
			MaximumReadyCount = METADATA.Summon.MaximumReadyCount,
			AtMaximum = readyCount >= METADATA.Summon.MaximumReadyCount,
			TotalBankedSouls = readyCount
					* METADATA.Summon.SoulsPerCharge
				+ rawSouls,
		}
	end

	function Summoner.GetEnergyState()
		return Energy.GetState()
	end

	function Summoner.GetSummonState()
		return MobsAPI.GetOwnedSummary(GameContext.GetLocalPlayer())
	end

	function Summoner.IsUltimateReady()
		return Energy.IsFull()
	end

	function Summoner.GetTargetDistance(target)
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

	function Summoner.EnsureUnsheathed()
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

	function Summoner.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Summoner.IsUltimateReady()
		end

		return true
	end

	function Summoner.CanSummon(minimumReadyCount)
		local canUse, useError = Summoner.CanUse(METADATA.Summon.Slot)

		if not canUse then
			return false, useError
		end

		local required = math.clamp(
			tonumber(minimumReadyCount) or 1,
			1,
			METADATA.Summon.MaximumReadyCount
		)

		if Summoner.GetSoulState().ReadyCount < required then
			return false, "not_enough_ready_summons"
		end

		return true
	end

	function Summoner.Use(slot)
		local canUse, reason = Summoner.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Summoner.UsePrimary()
		return Summoner.Use(METADATA.Primary.Slot)
	end

	function Summoner.UseSummon(minimumReadyCount)
		local canUse, reason = Summoner.CanSummon(minimumReadyCount)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.Summon.Slot)
	end

	function Summoner.UseRiftExplosion()
		return Summoner.Use(METADATA.RiftExplosion.Slot)
	end

	function Summoner.UseSoulHarvest()
		return Summoner.Use(METADATA.SoulHarvest.Slot)
	end

	function Summoner.UseUltimate()
		return Summoner.Use(METADATA.Ultimate.Slot)
	end

	function Summoner.UseDodge()
		return Summoner.Use(METADATA.Dodge.Slot)
	end

	return Summoner
end
