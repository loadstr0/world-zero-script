return function(ctx)
	local Starbreaker = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Starbreaker",
		AutomationRange = 45,
		Primary = {
			Slot = "Primary",
			Name = "Stellar Slash",
			ComboSteps = 5,
			DamageEvents = 8,
			ComboReset = 1.2,
			Range = 16,
			ConeAngle = 45,
			StarforgeSpeedMultiplier = 1.2,
			StarforgeCreatesWaves = true,
			FusionChangesToHeavySlam = true,
		},
		Nova = {
			Slot = "Skill1",
			Cooldown = 7,
			NormalStrikeCount = 3,
			NormalRadius = 10,
			SupernovaRadius = 15,
			SupernovaWindow = 4,
			NormalChargePerStrike = 10,
			SupernovaCharge = 20,
		},
		Flare = {
			Slot = "Skill2",
			Cooldown = 10,
			Duration = 8,
			SeeksTargets = true,
			StarforgeFlareCount = 2,
		},
		Starforge = {
			Slot = "Skill3",
			Cooldown = 25,
			RequiredCharge = 100,
			Duration = 15,
			FieldPulseCount = 10,
			FieldPulseInterval = 1.4,
			FieldRadius = 20,
			SlowDuration = 3,
			DamageResistance = 0.6,
			MaximumTargetDistance = 120,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Fusion Fall",
			Cooldown = 30,
			RequiresFullEnergy = true,
			FusionDuration = 21,
			FreeStarforgeDelay = 1,
			FreeStarforgeDuration = 20,
			ChangesPrimaryToHeavySlam = true,
		},
		PerkSwap = {
			Slot = "SwapPerk",
			Cooldown = 1,
		},
		Dodge = {
			Slot = "Dodge",
		},
	}

	local function getProperty(name)
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		return properties and properties:FindFirstChild(name)
	end

	function Starbreaker.Describe()
		return METADATA
	end

	function Starbreaker.GetStarforgeState()
		local chargeValue = getProperty("StarforgeCharge")
		local supernova = getProperty("SupernovaReady")
		local fusion = getProperty("FusionActive")
		local charge = chargeValue and tonumber(chargeValue.Value) or 0

		return {
			Charge = charge,
			MaximumCharge = METADATA.Starforge.RequiredCharge,
			Ready = charge >= METADATA.Starforge.RequiredCharge,
			Active = Status.Has("Starforge"),
			SupernovaReady = supernova ~= nil and supernova.Value == true,
			FusionActive = fusion ~= nil and fusion.Value == true,
		}
	end

	function Starbreaker.GetEnergyState()
		return Energy.GetState()
	end

	function Starbreaker.IsUltimateReady()
		return Energy.IsFull()
	end

	function Starbreaker.GetTargetDistance(target)
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

	function Starbreaker.EnsureUnsheathed()
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

	function Starbreaker.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Starbreaker.IsUltimateReady()
		end

		return true
	end

	function Starbreaker.CanActivateStarforge()
		local canUse, useError = Starbreaker.CanUse(METADATA.Starforge.Slot)

		if not canUse then
			return false, useError
		end

		local state = Starbreaker.GetStarforgeState()

		if not state.Ready then
			return false, "starforge_charge_not_full"
		end

		if state.Active then
			return false, "starforge_already_active"
		end

		return true
	end

	function Starbreaker.Use(slot)
		local canUse, reason = Starbreaker.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Starbreaker.UsePrimary()
		return Starbreaker.Use(METADATA.Primary.Slot)
	end

	function Starbreaker.UseNova()
		return Starbreaker.Use(METADATA.Nova.Slot)
	end

	function Starbreaker.UseFlare()
		return Starbreaker.Use(METADATA.Flare.Slot)
	end

	function Starbreaker.UseStarforge()
		local canUse, reason = Starbreaker.CanActivateStarforge()

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.Starforge.Slot)
	end

	function Starbreaker.UseUltimate()
		return Starbreaker.Use(METADATA.Ultimate.Slot)
	end

	function Starbreaker.UsePerkSwap()
		return Starbreaker.Use(METADATA.PerkSwap.Slot)
	end

	function Starbreaker.UseDodge()
		return Starbreaker.Use(METADATA.Dodge.Slot)
	end

	return Starbreaker
end
