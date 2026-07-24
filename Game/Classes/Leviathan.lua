return function(ctx)
	local Leviathan = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Leviathan",
		AutomationRange = 40,
		Primary = {
			Slot = "Primary",
			Name = "Serpent's Fang",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 6,
			ComboReset = 1,
			AnimationSpeed = 1.5,
			CriticalBubbleDuration = 5,
			CriticalBubbleDamageRatio = 0.45,
		},
		Riptide = {
			Slot = "Skill1",
			Name = "Water Cyclone",
			TravelDistance = 30,
			GroundBubbleCount = 5,
			GroundBubbleDuration = 5,
			GroundBubbleDamageRatio = 0.45,
			ChainStep = 1,
		},
		Hydrosurge = {
			Slot = "Skill2",
			SweepDistance = 40,
			BubblePopRadius = 12,
			SerpentsPerBubble = 3,
			SerpentDamageRatio = 0.4,
			SerpentRadius = 18,
			ChainStep = 2,
		},
		Maelstrom = {
			Slot = "Skill3",
			Duration = 6,
			HitInterval = 0.5,
			SeaBubbleDuration = 8,
			KillHealRatio = 0.05,
			KillHealRadius = 20,
			ChainStep = 3,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Leviathan's Wrath",
			RequiresFullEnergy = true,
			Duration = 7,
			InvincibleDuration = 7,
			DashSpeed = 36,
			DashDelay = 2.1,
			DirectHitCount = 8,
			SerpentsPerHit = 3,
			MaximumSerpentCount = 24,
			SerpentDamageRatio = 0.4,
			SerpentRadius = 18,
			FinalBubblePopRadius = 40,
			InflictsDrench = true,
			InflictsStun = true,
		},
		Dodge = {
			Slot = "Dodge",
			AnimationSpeed = 1.25,
		},
	}

	local CHAIN_LABELS = {
		[0] = "Water Cyclone",
		[2] = "Hydrosurge",
		[3] = "Maelstrom Spin",
	}

	function Leviathan.Describe()
		return METADATA
	end

	function Leviathan.GetChainState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local chainedState = properties and properties:FindFirstChild("ChainedState")

		return chainedState and tonumber(chainedState.Value) or 0
	end

	function Leviathan.GetChainLabel()
		local state = Leviathan.GetChainState()
		return CHAIN_LABELS[state] or ("Unknown state " .. tostring(state))
	end

	function Leviathan.IsSeaBubbleActive()
		return Status.Has("SeaBubble")
	end

	function Leviathan.IsInvincible()
		return Status.Has("Invincible")
	end

	function Leviathan.GetEnergyState()
		return Energy.GetState()
	end

	function Leviathan.IsUltimateReady()
		return Energy.IsFull()
	end

	function Leviathan.EnsureUnsheathed()
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

	function Leviathan.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Leviathan.IsUltimateReady()
		end

		return true
	end

	function Leviathan.Use(slot)
		local canUse, reason = Leviathan.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Leviathan.UsePrimary()
		return Leviathan.Use(METADATA.Primary.Slot)
	end

	function Leviathan.UseRiptide()
		return Leviathan.Use(METADATA.Riptide.Slot)
	end

	function Leviathan.UseHydrosurge()
		return Leviathan.Use(METADATA.Hydrosurge.Slot)
	end

	function Leviathan.UseMaelstrom()
		return Leviathan.Use(METADATA.Maelstrom.Slot)
	end

	function Leviathan.UseUltimate()
		return Leviathan.Use(METADATA.Ultimate.Slot)
	end

	function Leviathan.UseDodge()
		return Leviathan.Use(METADATA.Dodge.Slot)
	end

	return Leviathan
end
