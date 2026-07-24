return function(ctx)
	local Status = {}

	local GameContext = ctx:Require("GameContext")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Status")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_status_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_status_require_failed"
		end

		cachedModule = result
		return cachedModule
	end

	function Status.Has(statusName, character)
		local module, resolveError = resolve()

		if not module then
			return false, resolveError
		end

		if type(module.HasStatus) ~= "function" then
			return false, "shared_status_missing_has_status"
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return false, "character_unavailable"
		end

		local ok, result = pcall(module.HasStatus, module, character, statusName)

		if not ok then
			return false, "status_query_failed"
		end

		return result ~= nil and result ~= false
	end

	function Status.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasStatusQuery = module and type(module.HasStatus) == "function" or false,
		}
	end

	return Status
end
