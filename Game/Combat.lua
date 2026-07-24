return function(ctx)
	local CombatAPI = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Combat")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_combat_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok then
			return nil, "shared_combat_require_failed:" .. tostring(result)
		end

		if type(result) ~= "table" then
			return nil, "shared_combat_invalid_export"
		end

		cachedModule = result
		return cachedModule
	end

	function CombatAPI.GetModule()
		return resolve()
	end

	function CombatAPI.GetTargetsInRadius(radius, height)
		local module, resolveError = resolve()

		if not module then
			return nil, nil, resolveError
		end

		if type(module.GetInRadius) ~= "function" then
			return nil, nil, "shared_combat_missing_get_in_radius"
		end

		local character = GameContext.GetCharacter()
		local root = GameContext.GetRootPart()

		if not character or not root then
			return nil, nil, "character_unavailable"
		end

		local ok, targets, positions = pcall(function()
			return module:GetInRadius(
				root.Position,
				tonumber(height) or 20,
				tonumber(radius) or 15,
				false,
				false,
				character,
				nil,
				true
			)
		end)

		if not ok then
			return nil, nil, "shared_combat_radius_scan_failed:" .. tostring(targets)
		end

		if type(targets) ~= "table" then
			return nil, nil, "shared_combat_radius_scan_invalid"
		end

		return targets, positions or {}
	end

	function CombatAPI.CountTargetsInRadius(radius, height)
		local targets, _, scanError = CombatAPI.GetTargetsInRadius(radius, height)

		if not targets then
			return nil, scanError
		end

		return #targets
	end

	function CombatAPI.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasRadiusScan = module and type(module.GetInRadius) == "function" or false,
			HasConeScan = module and type(module.GetInCone) == "function" or false,
			ServerRebuildsHitboxes = true,
			ServerRateLimitsSkills = true,
			DirectAttackTargetFlagged = true,
			InvalidDamageIdFlagged = true,
		}
	end

	return CombatAPI
end
