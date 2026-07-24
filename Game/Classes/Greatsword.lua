return function(ctx)
	local Greatsword = {}

	local Actions = ctx:Require("Actions")

	local METADATA = {
		ClassName = "Greatsword",
		AutomationReady = false,
		AutomationUnavailableReason = "supplied_skillset_is_non_damaging_prototype",
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			ComboSteps = 3,
			ComboReset = 0.75,
			AnimationSet = "DualWielder",
			VerifiedDamageCall = false,
			HitBehavior = "print_only",
		},
		Skills = {},
	}

	function Greatsword.Describe()
		return METADATA
	end

	function Greatsword.CanUsePrimary()
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(METADATA.Primary.Slot) == true then
			return false, "cooldown"
		end

		return true
	end

	function Greatsword.UsePrimary()
		local canUse, reason = Greatsword.CanUsePrimary()

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(METADATA.Primary.Slot)
	end

	return Greatsword
end
