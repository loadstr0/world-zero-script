return function(ctx)
	local Warlord = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")

	local METADATA = {
		ClassName = "Warlord",
		AutomationRange = 40,
		Primary = {
			Slot = "Primary",
			Name = "Warlord's Rage",
			Range = 16,
			ConeAngle = 45,
			ComboSteps = 4,
			ComboReset = 1,
		},
		Piledriver = {
			Slot = "Skill1",
			Cooldown = 5,
			MaximumChain = 3,
			ChainWindow = 3.5,
			Radius = 12,
			ForwardOffset = 6,
			AnimationSpeed = 1.5,
			MovementMultiplier = 0.65,
			MaximumDamageMultiplier = 2,
		},
		ChargedBlock = {
			Slot = "Skill2",
			Cooldown = 3,
			Duration = 2,
			DamageReduction = 0.8,
			CounterAppliesShock = true,
		},
		ChainsOfWar = {
			Slot = "Skill3",
			Cooldown = 11,
			Radius = 40,
			DefenseReduction = 0.5,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Yggdrasil",
			Cooldown = 30,
			RequiresFullEnergy = true,
			EffectRange = 80,
			Duration = 18,
			PulseCount = 5,
			PulseSpacing = 3.6,
			MovableBossSlowDuration = 2,
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

	function Warlord.Describe()
		return METADATA
	end

	function Warlord.GetState()
		local blocking = getProperty("Blocking")

		return {
			Blocking = blocking ~= nil and blocking.Value == true,
		}
	end

	function Warlord.GetHealthState()
		return Health.GetState()
	end

	function Warlord.GetEnergyState()
		return Energy.GetState()
	end

	function Warlord.IsUltimateReady()
		return Energy.IsFull()
	end

	function Warlord.GetTargetDistance(target)
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

	function Warlord.EnsureUnsheathed()
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

	function Warlord.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Warlord.IsUltimateReady()
		end

		return true
	end

	function Warlord.CanBlock()
		local canUse, useError = Warlord.CanUse(METADATA.ChargedBlock.Slot)

		if not canUse then
			return false, useError
		end

		if Warlord.GetState().Blocking then
			return false, "already_blocking"
		end

		return true
	end

	function Warlord.Use(slot)
		local canUse, reason = Warlord.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Warlord.UsePrimary()
		return Warlord.Use(METADATA.Primary.Slot)
	end

	function Warlord.UsePiledriver()
		return Warlord.Use(METADATA.Piledriver.Slot)
	end

	function Warlord.UseBlock()
		local canUse, reason = Warlord.CanBlock()

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.ChargedBlock.Slot)
	end

	function Warlord.UseChainsOfWar()
		return Warlord.Use(METADATA.ChainsOfWar.Slot)
	end

	function Warlord.UseUltimate()
		return Warlord.Use(METADATA.Ultimate.Slot)
	end

	function Warlord.UsePerkSwap()
		return Warlord.Use(METADATA.PerkSwap.Slot)
	end

	function Warlord.UseDodge()
		return Warlord.Use(METADATA.Dodge.Slot)
	end

	return Warlord
end
