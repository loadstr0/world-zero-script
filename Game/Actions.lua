return function(ctx)
	local Actions = {}

	local Logger = ctx:Require("Logger")
	local GameContext = ctx:Require("GameContext")
	local Executor = ctx:Require("Executor")
	local cachedModule = nil
	local targetProvider = nil
	local internalTargetOverrideEnabled = false
	local internalTargetOverrideClass = nil
	local internalTargetOverrideRange = nil
	local internalTargetOverrideWrapper = nil
	local originalInternalGetNearestTarget = nil
	local hookedInternalGetNearestTarget = nil
	local internalTargetOverrideUsesExecutorHook = false
	local forcedInternalTarget = nil
	local forcedInternalTargetUntil = 0
	local cachedCombatModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Client.Actions")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "client_actions_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok then
			return nil, "client_actions_require_failed:" .. tostring(result)
		end

		if type(result) ~= "table" then
			return nil, "client_actions_invalid_export"
		end

		cachedModule = result
		return cachedModule
	end

	local function call(methodName, ...)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		local method = module[methodName]

		if type(method) ~= "function" then
			return nil, "client_actions_missing_method:" .. tostring(methodName)
		end

		local results = table.pack(pcall(method, module, ...))

		if not results[1] then
			Logger.warn("Client.Actions call failed:", methodName, results[2])
			return nil, "client_actions_call_failed:" .. tostring(methodName)
		end

		return table.unpack(results, 2, results.n)
	end

	local function getEquippedClass()
		local player = GameContext.GetLocalPlayer()

		if not player then
			return nil
		end

		local className = player:GetAttribute("Class")
		local character = player.Character
		local properties = character and character:FindFirstChild("Properties")

		if not className and properties then
			className = properties:GetAttribute("Class")
		end

		return className
	end

	local function targetFitsRequestedRange(target, radius, character)
		if typeof(target) ~= "Instance" or target.Parent == nil then
			return false
		end

		local targetPart = target.PrimaryPart
			or target:FindFirstChild("HumanoidRootPart")
			or target:FindFirstChild("Collider")

		if not targetPart or not targetPart:IsA("BasePart") then
			return false
		end

		local sourceCharacter = character

		if typeof(sourceCharacter) ~= "Instance" or not sourceCharacter:IsA("Model") then
			sourceCharacter = GameContext.GetCharacter()
		end

		local sourcePart = sourceCharacter
			and (
				sourceCharacter:FindFirstChild("HumanoidRootPart")
				or sourceCharacter.PrimaryPart
			)
		local numericRadius = tonumber(radius)

		if not sourcePart or not numericRadius or numericRadius == math.huge then
			return sourcePart ~= nil
		end

		return (targetPart.Position - sourcePart.Position).Magnitude <= numericRadius
	end

	local function resolveCombat()
		if type(cachedCombatModule) == "table" then
			return cachedCombatModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Combat")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_combat_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_combat_require_failed:" .. tostring(result)
		end

		cachedCombatModule = result
		return result
	end

	local function restoreInternalTargetOverride()
		local module = cachedModule

		if internalTargetOverrideUsesExecutorHook and hookedInternalGetNearestTarget then
			if Executor.Has("RestoreFunction") then
				pcall(Executor.RestoreFunction, hookedInternalGetNearestTarget)
			elseif
				Executor.Has("HookFunction")
				and type(originalInternalGetNearestTarget) == "function"
			then
				pcall(
					Executor.HookFunction,
					hookedInternalGetNearestTarget,
					originalInternalGetNearestTarget
				)
			end
		elseif
			type(module) == "table"
			and internalTargetOverrideWrapper
			and module.GetNearestTarget == internalTargetOverrideWrapper
			and type(originalInternalGetNearestTarget) == "function"
		then
			module.GetNearestTarget = originalInternalGetNearestTarget
		end

		internalTargetOverrideWrapper = nil
		originalInternalGetNearestTarget = nil
		hookedInternalGetNearestTarget = nil
		internalTargetOverrideUsesExecutorHook = false
	end

	local function installInternalTargetOverride()
		if not internalTargetOverrideEnabled then
			restoreInternalTargetOverride()
			return false, "internal_target_override_inactive"
		end

		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if
			internalTargetOverrideWrapper
			and (
				internalTargetOverrideUsesExecutorHook
				or module.GetNearestTarget == internalTargetOverrideWrapper
			)
		then
			return true
		end

		restoreInternalTargetOverride()

		local original = module.GetNearestTarget

		if type(original) ~= "function" then
			return false, "client_actions_missing_method:GetNearestTarget"
		end

		local fallbackOriginal = original
		local replacement = function(self, radius, character)
			local classAllowed = internalTargetOverrideClass == nil
				or getEquippedClass() == internalTargetOverrideClass

			if classAllowed then
				local target = nil
				local allowedRadius = math.max(
					tonumber(radius) or 0,
					tonumber(internalTargetOverrideRange) or 0
				)

				if
					forcedInternalTarget
					and os.clock() <= forcedInternalTargetUntil
					and targetFitsRequestedRange(
						forcedInternalTarget,
						allowedRadius,
						character
					)
				then
					target = forcedInternalTarget
				elseif os.clock() > forcedInternalTargetUntil then
					forcedInternalTarget = nil
					forcedInternalTargetUntil = 0
				end

				if target then
					return target
				end

				if type(targetProvider) ~= "function" then
					return fallbackOriginal(self, radius, character)
				end

				local ok
				ok, target = pcall(targetProvider, radius, character)

				if
					ok
					and targetFitsRequestedRange(
						target,
						allowedRadius,
						character
					)
				then
					return target
				elseif not ok then
					Logger.warn("Internal target provider failed:", target)
				end
			end

			return fallbackOriginal(self, radius, character)
		end

		if Executor.Has("HookFunction") and Executor.Has("RestoreFunction") then
			local callback = replacement

			if Executor.Has("NewCClosure") then
				local wrappedOk, wrapped = pcall(Executor.NewCClosure, replacement)

				if wrappedOk and type(wrapped) == "function" then
					callback = wrapped
				end
			end

			local hookOk, old = pcall(Executor.HookFunction, original, callback)

			if hookOk and type(old) == "function" then
				fallbackOriginal = old
				originalInternalGetNearestTarget = old
				hookedInternalGetNearestTarget = original
				internalTargetOverrideWrapper = callback
				internalTargetOverrideUsesExecutorHook = true
				return true
			end
		end

		originalInternalGetNearestTarget = original
		internalTargetOverrideWrapper = replacement
		module.GetNearestTarget = replacement

		return true
	end

	function Actions.IsAvailable()
		return resolve() ~= nil
	end

	function Actions.GetModule()
		return resolve()
	end

	function Actions.UseSkill(skillSlot)
		return call("UseSkill", skillSlot)
	end

	function Actions.GetNearestTarget(radius, character)
		if type(targetProvider) == "function" then
			local ok, target = pcall(targetProvider, radius, character)

			if not ok then
				Logger.warn("Custom target provider failed:", target)
				return nil, "target_provider_failed"
			end

			return target
		end

		return call("GetNearestTarget", radius, character)
	end

	function Actions.AimAtNearestTarget(duration, radius)
		if type(targetProvider) == "function" then
			local target, targetError = Actions.GetNearestTarget(radius)

			if not target then
				return nil, targetError or "target_unavailable"
			end

			return call("AimAtMob", target, duration)
		end

		return call("AimAtNearestMob", duration, radius)
	end

	function Actions.AimAtTarget(target, duration)
		if not target then
			return nil, "target_unavailable"
		end

		return call("AimAtMob", target, duration)
	end

	function Actions.SetTargetProvider(provider)
		if provider ~= nil and type(provider) ~= "function" then
			return false, "target_provider_must_be_function"
		end

		targetProvider = provider
		installInternalTargetOverride()
		return true
	end

	function Actions.ClearTargetProvider(provider)
		if provider == nil or provider == targetProvider then
			targetProvider = nil
			restoreInternalTargetOverride()
			return true
		end

		return false, "target_provider_changed"
	end

	function Actions.SetInternalTarget(target, duration)
		if target == nil then
			forcedInternalTarget = nil
			forcedInternalTargetUntil = 0
			return true
		end

		if typeof(target) ~= "Instance" then
			return false, "internal_target_must_be_instance"
		end

		forcedInternalTarget = target
		forcedInternalTargetUntil = os.clock()
			+ math.max(0.25, tonumber(duration) or 2)

		if internalTargetOverrideEnabled then
			installInternalTargetOverride()
		end

		return true
	end

	function Actions.SetInternalTargetOverride(enabled, className, rangeOverride)
		internalTargetOverrideEnabled = enabled == true
		internalTargetOverrideClass = internalTargetOverrideEnabled
				and (className or internalTargetOverrideClass)
			or nil
		internalTargetOverrideRange = internalTargetOverrideEnabled
				and (tonumber(rangeOverride) or internalTargetOverrideRange)
			or nil

		if internalTargetOverrideEnabled then
			return installInternalTargetOverride()
		end

		restoreInternalTargetOverride()
		forcedInternalTarget = nil
		forcedInternalTargetUntil = 0
		return true
	end

	function Actions.UseSkillWithLineOfSightBypass(skillSlot)
		local combat, combatError = resolveCombat()

		if not combat then
			return nil, combatError
		end

		local canSee = combat.CanSeeWithRay

		if type(canSee) ~= "function" then
			return Actions.UseSkill(skillSlot)
		end

		local hookTarget = nil
		local usedExecutorHook = false
		local replacement = function()
			return true
		end

		if Executor.Has("HookFunction") and Executor.Has("RestoreFunction") then
			if Executor.Has("NewCClosure") then
				local wrappedOk, wrapped = pcall(Executor.NewCClosure, replacement)

				if wrappedOk and type(wrapped) == "function" then
					replacement = wrapped
				end
			end

			local hookOk = pcall(Executor.HookFunction, canSee, replacement)

			if hookOk then
				hookTarget = canSee
				usedExecutorHook = true
			end
		end

		if not usedExecutorHook then
			combat.CanSeeWithRay = replacement
		end

		local results = table.pack(Actions.UseSkill(skillSlot))

		if usedExecutorHook then
			pcall(Executor.RestoreFunction, hookTarget)
		elseif combat.CanSeeWithRay == replacement then
			combat.CanSeeWithRay = canSee
		end

		return table.unpack(results, 1, results.n)
	end

	function Actions.GetRemainingCooldown(skillSlot)
		return call("GetRemainingCooldown", skillSlot)
	end

	function Actions.IsOnCooldown(skillSlot)
		return call("IsOnCooldown", skillSlot)
	end

	function Actions.IsBusy()
		return call("IsBusy")
	end

	function Actions.ResumeMovement()
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		local called = false

		for _, methodName in ipairs({
			"ResumeCharacterMovement",
			"UnlockMovement",
		}) do
			local method = module[methodName]

			if type(method) == "function" then
				local ok = pcall(method)

				if not ok then
					ok = pcall(method, module)
				end

				called = called or ok
			end
		end

		return called, called and nil or "client_movement_resume_failed"
	end

	function Actions.IsMounted()
		return call("IsMounted")
	end

	function Actions.IsSheathed(character)
		return call("IsSheathed", character)
	end

	function Actions.Sprint()
		return call("Sprint")
	end

	function Actions.StopSprint()
		return call("StopSprint")
	end

	function Actions.ToggleMount(autoDismount)
		return call("ToggleMount", autoDismount)
	end

	function Actions.UseQuickItem(itemName)
		return call("UseQuickItem", itemName)
	end

	function Actions.Sheath()
		return call("Sheath")
	end

	function Actions.Describe()
		local module, resolveError = resolve()

		if not module then
			return {
				Available = false,
				Error = resolveError,
			}
		end

		return {
			Available = true,
			Initialized = module.SkillUsedSignal ~= nil,
			HasUseSkill = type(module.UseSkill) == "function",
			HasTargeting = type(module.GetNearestTarget) == "function",
			HasCooldowns = type(module.GetRemainingCooldown) == "function",
			HasMovement = type(module.Sprint) == "function",
			InternalTargetOverride = internalTargetOverrideWrapper ~= nil
				and (
					internalTargetOverrideUsesExecutorHook
					or module.GetNearestTarget == internalTargetOverrideWrapper
				),
			InternalTargetOverrideClass = internalTargetOverrideClass,
			InternalTargetOverrideRange = internalTargetOverrideRange,
			InternalTargetOverrideUsesExecutorHook =
				internalTargetOverrideUsesExecutorHook,
			CanResumeMovement =
				type(module.ResumeCharacterMovement) == "function"
				or type(module.UnlockMovement) == "function",
		}
	end

	return Actions
end
