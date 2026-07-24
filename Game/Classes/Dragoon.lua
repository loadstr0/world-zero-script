return function(ctx)
	local Dragoon = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")

	local METADATA = {
		ClassName = "Dragoon",
		AutomationRange = 30,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 6,
			ComboReset = 1,
			MarkDuration = 10,
			MarkedSkillDamageBonus = 0.2,
		},
		InfinityStrike = {
			Slot = "Skill1",
			Range = 30,
			CrossHits = 10,
			ChainStep = 1,
		},
		DragonWrath = {
			Slot = "Skill2",
			Range = 20,
			HitCount = 5,
			ChainStep = 2,
		},
		DragonSlam = {
			Slot = "Skill3",
			Radius = 15,
			ChainStep = 3,
			CompletedDragonModeDuration = 8,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Dragon Dance",
			RequiresFullEnergy = true,
			InitialRadius = 40,
			DragonCount = 18,
			DragonModeDuration = 16,
		},
		Dodge = {
			Slot = "Dodge",
			HasBackstep = true,
		},
	}

	local CHAIN_LABELS = {
		[0] = "Waiting for a critical hit",
		[1] = "Infinity Strike",
		[2] = "Dragon Wrath",
		[3] = "Dragon Slam",
		[-1] = "Dragon Mode activating",
	}

	function Dragoon.Describe()
		return METADATA
	end

	function Dragoon.GetChainState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local chainedState = properties and properties:FindFirstChild("ChainedState")

		return chainedState and tonumber(chainedState.Value) or 0
	end

	function Dragoon.GetChainLabel()
		local state = Dragoon.GetChainState()
		return CHAIN_LABELS[state] or ("Unknown state " .. tostring(state))
	end

	function Dragoon.IsDragonMode()
		return Status.Has("DragonBuff")
	end

	function Dragoon.GetEnergyState()
		return Energy.GetState()
	end

	function Dragoon.IsUltimateReady()
		return Energy.IsFull()
	end

	function Dragoon.EnsureUnsheathed()
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

	function Dragoon.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Dragoon.IsUltimateReady()
		end

		return true
	end

	function Dragoon.Use(slot)
		local canUse, reason = Dragoon.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Dragoon.UsePrimary()
		return Dragoon.Use(METADATA.Primary.Slot)
	end

	function Dragoon.UseInfinityStrike()
		return Dragoon.Use(METADATA.InfinityStrike.Slot)
	end

	function Dragoon.UseDragonWrath()
		return Dragoon.Use(METADATA.DragonWrath.Slot)
	end

	function Dragoon.UseDragonSlam()
		return Dragoon.Use(METADATA.DragonSlam.Slot)
	end

	function Dragoon.UseUltimate()
		return Dragoon.Use(METADATA.Ultimate.Slot)
	end

	function Dragoon.UseDodge()
		return Dragoon.Use(METADATA.Dodge.Slot)
	end

	return Dragoon
end
