return function(ctx)
	local Defender = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players

	local METADATA = {
		ClassName = "Defender",
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 5,
			ComboReset = 1,
		},
		Groundbreaker = {
			Slot = "Skill1",
			Radius = 8,
		},
		CycloneSwing = {
			Slot = "Skill2",
			Radius = 9,
			HitCount = 8,
		},
		Ultimate = {
			Slot = "Ultimate",
			Name = "Defender's Shield",
			RequiresFullEnergy = true,
			Radius = 50,
			HealingChecks = 7,
			HealingStatusDuration = 5,
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

	function Defender.Describe()
		return METADATA
	end

	function Defender.GetEnergyState()
		return Energy.GetState()
	end

	function Defender.IsUltimateReady()
		return Energy.IsFull()
	end

	function Defender.GetNearbyAllies(radius)
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
				local humanoid = character and character:FindFirstChildOfClass("Humanoid")

				if
					root
					and humanoid
					and humanoid.Health > 0
					and (root.Position - localRoot.Position).Magnitude <= (tonumber(radius) or 50)
				then
					table.insert(result, {
						Player = player,
						Character = character,
						Health = humanoid.Health,
						MaxHealth = humanoid.MaxHealth,
						HealthRatio = humanoid.MaxHealth > 0
								and humanoid.Health / humanoid.MaxHealth
							or 1,
					})
				end
			end
		end

		return result
	end

	function Defender.CountNearbyAllies(radius)
		return #Defender.GetNearbyAllies(radius)
	end

	function Defender.HasInjuredAlly(radius, healthPercent)
		local threshold = math.clamp((tonumber(healthPercent) or 40) / 100, 0, 1)

		for _, ally in ipairs(Defender.GetNearbyAllies(radius)) do
			if ally.HealthRatio <= threshold then
				return true, ally
			end
		end

		return false
	end

	function Defender.EnsureUnsheathed()
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

	function Defender.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return Defender.IsUltimateReady()
		end

		return true
	end

	function Defender.Use(slot)
		local canUse, reason = Defender.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	function Defender.UsePrimary()
		return Defender.Use(METADATA.Primary.Slot)
	end

	function Defender.UseGroundbreaker()
		return Defender.Use(METADATA.Groundbreaker.Slot)
	end

	function Defender.UseCycloneSwing()
		return Defender.Use(METADATA.CycloneSwing.Slot)
	end

	function Defender.UseUltimate()
		return Defender.Use(METADATA.Ultimate.Slot)
	end

	function Defender.UseDodge()
		return Defender.Use(METADATA.Dodge.Slot)
	end

	return Defender
end
