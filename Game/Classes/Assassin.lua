return function(ctx)
	local Assassin = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")

	local METADATA = {
		ClassName = "Assassin",
		AutomationRange = 60,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			DamageVariants = 8,
			ShadowDamageMultiplier = 1.2,
		},
		ShadowCloak = {
			Slot = "Skill1",
			Duration = 5,
			MovementMultiplier = 1.6,
			GuaranteedCriticals = true,
		},
		ShadowLeap = {
			Slot = "Skill2",
			Range = 60,
			TeleportsBehindTarget = true,
		},
		ShadowStrike = {
			Slot = "Skill3",
			Radius = 15,
			HitCount = 2,
			GuaranteedCritical = true,
		},
		Ultimate = {
			Slot = "Ultimate",
			RequiresFullEnergy = true,
			ShadowModeDuration = 15,
		},
		Dodge = {
			Slot = "Dodge",
		},
		SwapPerk = {
			Slot = "SwapPerk",
		},
	}

	function Assassin.Describe()
		return METADATA
	end

	function Assassin.IsShadowMode()
		local character = GameContext.GetCharacter()
		return character ~= nil and character:FindFirstChild("StealthWalked") ~= nil
	end

	function Assassin.GetEnergyState()
		return Energy.GetState()
	end

	function Assassin.IsUltimateReady()
		if Assassin.IsShadowMode() then
			return false, "shadow_mode_active"
		end

		return Energy.IsFull()
	end

	function Assassin.EnsureUnsheathed()
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

	function Assassin.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.ShadowCloak.Slot and Assassin.IsShadowMode() then
			return false, "shadow_mode_active"
		end

		if slot == METADATA.Ultimate.Slot then
			return Assassin.IsUltimateReady()
		end

		return true
	end

	function Assassin.Use(slot)
		local canUse, reason = Assassin.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Assassin.UsePrimary()
		return Assassin.Use(METADATA.Primary.Slot)
	end

	function Assassin.UseShadowCloak()
		return Assassin.Use(METADATA.ShadowCloak.Slot)
	end

	function Assassin.UseShadowLeap()
		return Assassin.Use(METADATA.ShadowLeap.Slot)
	end

	function Assassin.UseShadowStrike()
		return Assassin.Use(METADATA.ShadowStrike.Slot)
	end

	function Assassin.UseUltimate()
		return Assassin.Use(METADATA.Ultimate.Slot)
	end

	function Assassin.UseDodge()
		return Assassin.Use(METADATA.Dodge.Slot)
	end

	function Assassin.SwapPerk()
		return Assassin.Use(METADATA.SwapPerk.Slot)
	end

	return Assassin
end
