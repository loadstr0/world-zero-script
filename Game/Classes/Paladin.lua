return function(ctx)
	local Paladin = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")
	local Status = ctx:Require("Status")
	local Players = ctx.Services.Players

	local METADATA = {
		ClassName = "Paladin",
		AutomationRange = 40,
		Primary = {
			Slot = "Primary",
			Name = "Noble Slash",
			ComboSteps = 4,
			NormalRange = 16,
			NormalConeAngle = 25,
			LightRange = 21,
			LightConeAngle = 45,
		},
		GildedBlock = {
			Slot = "Skill1",
			Cooldown = 3,
			BlockingWindow = 1,
			DamageReduction = 0.8,
			HealPerBlockedHit = 0.05,
			SplashRadius = 20,
			AggroRadius = 50,
		},
		DivineRetribution = {
			Slot = "Skill2",
			Cooldown = 14,
			Radius = 40,
			HealFromCasterMaximumHealth = 0.45,
			DefenseBoost = 0.45,
			BoostDuration = 9,
			CleansesCasterDebuffs = true,
		},
		LightThrust = {
			Slot = "Skill3",
			Cooldown = 11,
			TargetRange = 60,
			HitCount = 2,
			HitOffset = 23,
			LightDuration = 9,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Ring of Justice",
			Cooldown = 30,
			RequiresFullEnergy = true,
			Duration = 15,
			PulseCount = 15,
			PulseInterval = 1,
			Radius = 40,
			HealPerPulse = 0.05,
			LightDuration = 15,
			AggroChecks = 8,
			AggroInterval = 1.875,
			CleansesStatuses = true,
			ResetsJudgment = true,
		},
		PerkSwap = {
			Slot = "SwapPerk",
			Cooldown = 1,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	local function getCharacterRoot(character)
		return character
			and (
				character:FindFirstChild("HumanoidRootPart")
				or character:FindFirstChild("Collider")
				or character.PrimaryPart
			)
	end

	local function getPropertyBool(name)
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local value = properties and properties:FindFirstChild(name)

		return value ~= nil and value.Value == true
	end

	function Paladin.Describe()
		return METADATA
	end

	function Paladin.GetHealthState(character)
		return Health.GetState(character)
	end

	function Paladin.GetEnergyState()
		return Energy.GetState()
	end

	function Paladin.IsUltimateReady()
		return Energy.IsFull()
	end

	function Paladin.IsBlocking()
		return getPropertyBool("Blocking")
	end

	function Paladin.IsUltimateActive()
		return getPropertyBool("UltimateActive")
	end

	function Paladin.IsLightSwordActive()
		return getPropertyBool("LightSwordActive")
			or Status.Has("PaladinLightSword")
	end

	function Paladin.HasDefenseBoost()
		return Status.Has("RingOfJusticeBoost")
	end

	function Paladin.GetPrimaryRange()
		if Paladin.IsLightSwordActive() then
			return METADATA.Primary.LightRange
		end

		return METADATA.Primary.NormalRange
	end

	function Paladin.GetTargetDistance(target)
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

	function Paladin.GetNearbyAllies(radius)
		local localPlayer = GameContext.GetLocalPlayer()
		local localRoot = getCharacterRoot(GameContext.GetCharacter())
		local result = {}

		if not localPlayer or not localRoot then
			return result
		end

		for _, player in ipairs(Players:GetPlayers()) do
			if player ~= localPlayer then
				local character = player.Character
				local root = getCharacterRoot(character)

				if
					root
					and (root.Position - localRoot.Position).Magnitude
						<= (tonumber(radius) or METADATA.DivineRetribution.Radius)
				then
					local health = Health.GetState(character)

					if health and health.Alive then
						table.insert(result, {
							Player = player,
							Character = character,
							Health = health,
							HealthRatio = health.Ratio,
						})
					end
				end
			end
		end

		return result
	end

	function Paladin.CountNearbyAllies(radius)
		return #Paladin.GetNearbyAllies(radius)
	end

	function Paladin.HasInjuredAlly(radius, healthPercent)
		local threshold = math.clamp((tonumber(healthPercent) or 60) / 100, 0, 1)

		for _, ally in ipairs(Paladin.GetNearbyAllies(radius)) do
			if ally.HealthRatio <= threshold then
				return true, ally
			end
		end

		return false
	end

	function Paladin.EnsureUnsheathed()
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

	function Paladin.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Paladin.IsUltimateReady()
		end

		return true
	end

	function Paladin.Use(slot)
		local canUse, reason = Paladin.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Paladin.UsePrimary()
		return Paladin.Use(METADATA.Primary.Slot)
	end

	function Paladin.UseGildedBlock()
		return Paladin.Use(METADATA.GildedBlock.Slot)
	end

	function Paladin.UseDivineRetribution()
		return Paladin.Use(METADATA.DivineRetribution.Slot)
	end

	function Paladin.UseLightThrust()
		return Paladin.Use(METADATA.LightThrust.Slot)
	end

	function Paladin.UseUltimate()
		return Paladin.Use(METADATA.Ultimate.Slot)
	end

	function Paladin.UsePerkSwap()
		return Paladin.Use(METADATA.PerkSwap.Slot)
	end

	function Paladin.UseDodge()
		return Paladin.Use(METADATA.Dodge.Slot)
	end

	return Paladin
end
