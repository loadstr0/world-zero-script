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

	function Status.GetActive(character)
		local module, resolveError = resolve()

		if not module then
			return nil, resolveError
		end

		character = character or GameContext.GetCharacter()

		if not character then
			return nil, "character_unavailable"
		end

		local folder = character:FindFirstChild("Status")

		if not folder then
			return {}
		end

		local result = {}

		for _, statusObject in ipairs(folder:GetChildren()) do
			local info = nil
			local remaining = nil

			if type(module.GetStatusInfo) == "function" then
				local infoOk, infoValue =
					pcall(module.GetStatusInfo, module, statusObject.Name)

				if infoOk and type(infoValue) == "table" then
					info = infoValue
				end
			end

			if type(module.GetRemainingTime) == "function" then
				local timeOk, timeValue =
					pcall(module.GetRemainingTime, module, statusObject)

				if timeOk then
					remaining = tonumber(timeValue)
				end
			end

			table.insert(result, {
				Name = statusObject.Name,
				Info = info,
				Remaining = remaining,
				Object = statusObject,
			})
		end

		table.sort(result, function(a, b)
			return a.Name < b.Name
		end)

		return result
	end

	function Status.IsIncapacitated(character)
		local active, activeError = Status.GetActive(character)

		if not active then
			return false, activeError
		end

		for _, status in ipairs(active) do
			local info = status.Info or {}

			if
				status.Name == "Knockdown"
				or info.ActionsDisabled == true
				or info.SkillsDisabled == true
				or info.CanAct == false
				or tonumber(info.WalkspeedMultiplier) == 0
			then
				return true, status.Name
			end
		end

		return false
	end

	function Status.GetSummary(character)
		local active, activeError = Status.GetActive(character)

		if not active then
			return nil, activeError
		end

		local names = {}

		for _, status in ipairs(active) do
			table.insert(names, status.Name)
		end

		return {
			Count = #active,
			Names = names,
			Text = #names > 0 and table.concat(names, ", ") or "none",
		}
	end

	function Status.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasStatusQuery = module and type(module.HasStatus) == "function" or false,
			HasStatusListing = true,
			HasStatusInfo = module
				and type(module.GetStatusInfo) == "function"
				or false,
			HasRemainingTime = module
				and type(module.GetRemainingTime) == "function"
				or false,
		}
	end

	return Status
end
