return function(ctx)
	local DualWielder = {}

	local Actions = ctx:Require("Actions")
	local Energy = ctx:Require("Energy")
	local GameContext = ctx:Require("GameContext")
	local Status = ctx:Require("Status")
	local RunService = ctx.Services.RunService or game:GetService("RunService")
	local Workspace = ctx.Services.Workspace or game:GetService("Workspace")
	local airborneAimSerial = 0

	local SPEED_MULTIPLIERS = {
		[0] = 1,
		[1] = 1.05,
		[2] = 1.1,
		[3] = 1.15,
		[4] = 1.2,
		[5] = 1.25,
		[6] = 1.3,
		[7] = 1.35,
		[8] = 1.4,
		[9] = 1.45,
		[10] = 1.5,
	}

	local METADATA = {
		ClassName = "DualWielder",
		AutomationRange = 20,
		Primary = {
			Slot = "Primary",
			FunctionName = "Attack",
			Range = 14,
			ConeAngle = 25,
			ComboSteps = 8,
			ComboReset = 0.75,
			MaximumSpeedStacks = 10,
			MaximumSpeedMultiplier = 1.5,
			SpeedStackTimeout = 3,
		},
		AttackBuff = {
			Slot = "Skill1",
			Name = "Tempo",
			Duration = 6,
			MaximumSpeedStacks = 10,
			KillExtension = 4,
			KillHealRatio = 0.05,
		},
		LeapStrikes = {
			Slot = "Skill2",
			Name = "Dash Strike",
			Range = 14,
			ConeAngle = 45,
			AirbornePitchDegrees = -90,
			ImpactDelay = 0.5,
		},
		CrossSlash = {
			Slot = "Skill3",
			CrescentCount = 2,
		},
		Ultimate = {
			Slot = "Ultimate",
			RequiresFullEnergy = true,
			ConeHits = 9,
			FallingSwords = 16,
			SlamHits = 4,
			MaximumAttackEvents = 29,
			SlamRadius = 15,
			ShockwaveRadius = 10,
		},
		Dodge = {
			Slot = "Dodge",
		},
		SwapPerk = {
			Slot = "SwapPerk",
		},
	}

	function DualWielder.Describe()
		return METADATA
	end

	function DualWielder.GetSpeedState()
		local character = GameContext.GetCharacter()
		local properties = character and character:FindFirstChild("Properties")
		local attackSpeed = properties and properties:FindFirstChild("AttackSpeed")
		local stacks = attackSpeed and tonumber(attackSpeed.Value) or 0

		stacks = math.clamp(math.floor(stacks), 0, METADATA.Primary.MaximumSpeedStacks)

		return {
			Stacks = stacks,
			MaximumStacks = METADATA.Primary.MaximumSpeedStacks,
			Multiplier = SPEED_MULTIPLIERS[stacks] or 1,
			Tempo = Status.Has("DualWielderTempo"),
		}
	end

	function DualWielder.IsTempoActive()
		return Status.Has("DualWielderTempo")
	end

	function DualWielder.GetEnergyState()
		return Energy.GetState()
	end

	function DualWielder.IsUltimateReady()
		return Energy.IsFull()
	end

	function DualWielder.EnsureUnsheathed()
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

	function DualWielder.CanUse(slot)
		if Actions.IsBusy() == true then
			return false, "busy"
		end

		if Actions.IsOnCooldown(slot) == true then
			return false, "cooldown"
		end

		if slot == METADATA.Ultimate.Slot then
			return DualWielder.IsUltimateReady()
		end

		return true
	end

	function DualWielder.Use(slot)
		local canUse, reason = DualWielder.CanUse(slot)

		if not canUse then
			return nil, reason
		end

		return Actions.UseSkill(slot)
	end

	local function getTargetPart(target)
		if typeof(target) ~= "Instance" then
			return nil
		end

		if target:IsA("BasePart") then
			return target
		end

		return target.PrimaryPart
			or target:FindFirstChild("Collider")
			or target:FindFirstChild("HumanoidRootPart")
	end

	local function isAirborne(humanoid, root)
		if not humanoid or not root then
			return false
		end

		if humanoid.FloorMaterial == Enum.Material.Air then
			return true
		end

		local character = GameContext.GetCharacter()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = character and { character } or {}
		params.IgnoreWater = false

		local raycastOk, ground = pcall(
			Workspace.Raycast,
			Workspace,
			root.Position,
			Vector3.new(0, -5, 0),
			params
		)

		-- CFrame flight can leave FloorMaterial stale for several frames. A
		-- root with no supporting surface inside normal standing clearance is
		-- airborne regardless of that cached Humanoid property.
		return raycastOk and ground == nil
	end

	function DualWielder.PrepareTargetedSkill(slot, target)
		if slot ~= METADATA.LeapStrikes.Slot then
			return false
		end

		local humanoid = GameContext.GetHumanoid()
		local root = GameContext.GetRootPart()
		local targetPart = getTargetPart(target)

		if not root or not targetPart or not isAirborne(humanoid, root) then
			return false
		end

		airborneAimSerial = airborneAimSerial + 1
		local serial = airborneAimSerial
		local actionsModule = Actions.GetModule()
		local originalAimAtNearestMob = type(actionsModule) == "table"
				and actionsModule.AimAtNearestMob
			or nil
		local suppressedAimAtNearestMob = function()
			return true
		end
		local aimSuppressed = false

		if type(originalAimAtNearestMob) == "function" then
			aimSuppressed = pcall(function()
				actionsModule.AimAtNearestMob = suppressedAimAtNearestMob
			end)
		end

		local function restoreInternalAim()
			if
				aimSuppressed
				and type(actionsModule) == "table"
				and actionsModule.AimAtNearestMob == suppressedAimAtNearestMob
			then
				actionsModule.AimAtNearestMob = originalAimAtNearestMob
			end

			aimSuppressed = false
		end

		-- Dash Strike normally installs a horizontal AimAtNearestMob connection
		-- before yielding. Its method is suppressed only for this cast, while
		-- the deferred correction starts after UseSkill has marked the action
		-- busy and holds the server-sampled hit cone straight down.
		task.defer(function()
			task.wait()

			if
				serial ~= airborneAimSerial
				or not root.Parent
				or not targetPart.Parent
				or Actions.IsBusy() ~= true
			then
				restoreInternalAim()
				return
			end

			local originalAutoRotate = humanoid.AutoRotate
			local originalPlatformStand = humanoid.PlatformStand
			local deadline = os.clock() + METADATA.LeapStrikes.ImpactDelay + 0.12
			local connections = {}

			humanoid.AutoRotate = false
			humanoid.PlatformStand = true

			local function applyDownwardPitch()
				if
					serial ~= airborneAimSerial
					or os.clock() >= deadline
					or not root.Parent
					or not targetPart.Parent
				then
					for _, connection in ipairs(connections) do
						connection:Disconnect()
					end

					table.clear(connections)

					if humanoid.Parent then
						humanoid.AutoRotate = originalAutoRotate
						humanoid.PlatformStand = originalPlatformStand
					end

					restoreInternalAim()

					if root.Parent and targetPart.Parent then
						local position = root.Position
						local flatTarget = Vector3.new(
							targetPart.Position.X,
							position.Y,
							targetPart.Position.Z
						)

						if (flatTarget - position).Magnitude > 0.001 then
							root.CFrame = CFrame.lookAt(position, flatTarget)
						end
					end

					return
				end

				local position = root.Position
				local flatDirection = Vector3.new(
					targetPart.Position.X - position.X,
					0,
					targetPart.Position.Z - position.Z
				)

				if flatDirection.Magnitude <= 0.001 then
					local currentLook = root.CFrame.LookVector
					flatDirection = Vector3.new(currentLook.X, 0, currentLook.Z)
				end

				if flatDirection.Magnitude > 0.001 then
					root.CFrame = CFrame.lookAt(
						position,
						position + flatDirection.Unit
					) * CFrame.Angles(
						math.rad(METADATA.LeapStrikes.AirbornePitchDegrees),
						0,
						0
					)
					root.AssemblyAngularVelocity = Vector3.zero
				end
			end

			-- The skill's delayed server-hit callback resumes after Heartbeat,
			-- while its visual aim can also write during rendering. Cover both
			-- phases so the sampled LookVector is downward at the authoritative
			-- hit moment as well as on screen.
			table.insert(
				connections,
				RunService.Heartbeat:Connect(applyDownwardPitch)
			)
			table.insert(
				connections,
				RunService.RenderStepped:Connect(applyDownwardPitch)
			)
			applyDownwardPitch()
		end)

		return true
	end

	function DualWielder.UsePrimary()
		return DualWielder.Use(METADATA.Primary.Slot)
	end

	function DualWielder.UseAttackBuff()
		return DualWielder.Use(METADATA.AttackBuff.Slot)
	end

	function DualWielder.UseLeapStrikes()
		return DualWielder.Use(METADATA.LeapStrikes.Slot)
	end

	function DualWielder.UseCrossSlash()
		return DualWielder.Use(METADATA.CrossSlash.Slot)
	end

	function DualWielder.UseUltimate()
		return DualWielder.Use(METADATA.Ultimate.Slot)
	end

	function DualWielder.UseDodge()
		return DualWielder.Use(METADATA.Dodge.Slot)
	end

	function DualWielder.SwapPerk()
		return DualWielder.Use(METADATA.SwapPerk.Slot)
	end

	return DualWielder
end
