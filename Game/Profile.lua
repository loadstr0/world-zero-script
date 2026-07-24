return function(ctx)
	local Profile = {}

	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players
	local cachedModule = nil

	local function resolveModule()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Profile")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_profile_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok then
			return nil, "shared_profile_require_failed:" .. tostring(result)
		end

		if type(result) ~= "table" then
			return nil, "shared_profile_invalid_export"
		end

		cachedModule = result
		return cachedModule
	end

	function Profile.GetCurrentClass()
		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local attribute = player:GetAttribute("Class")

		if type(attribute) == "string" and attribute ~= "" then
			return attribute
		end

		local module, resolveError = resolveModule()

		if not module then
			return nil, resolveError
		end

		if type(module.GetClass) == "function" then
			local ok, className = pcall(module.GetClass, module, player)

			if ok and type(className) == "string" and className ~= "" then
				return className
			end
		end

		if type(module.GetProfile) ~= "function" then
			return nil, "shared_profile_missing_get_profile"
		end

		local ok, profile = pcall(module.GetProfile, module, player)

		if not ok or not profile then
			return nil, "player_profile_unavailable"
		end

		local classValue = profile:FindFirstChild("Class")

		if not classValue then
			return nil, "player_class_unavailable"
		end

		return tostring(classValue.Value)
	end

	function Profile.ObserveClass(callback)
		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		return player:GetAttributeChangedSignal("Class"):Connect(function()
			local className = player:GetAttribute("Class")

			if type(className) == "string" and className ~= "" then
				callback(className)
			end
		end)
	end

	function Profile.GetValue(valueName)
		local module, resolveError = resolveModule()

		if not module then
			return nil, resolveError
		end

		if type(module.GetProfile) ~= "function" then
			return nil, "shared_profile_missing_get_profile"
		end

		local player = Players.LocalPlayer

		if not player then
			return nil, "local_player_unavailable"
		end

		local ok, profile = pcall(module.GetProfile, module, player)

		if not ok or not profile then
			return nil, "player_profile_unavailable"
		end

		local valueObject = profile:FindFirstChild(valueName)

		if not valueObject then
			return nil, "profile_value_unavailable:" .. tostring(valueName)
		end

		return valueObject.Value
	end

	function Profile.Describe()
		local className, classError = Profile.GetCurrentClass()

		return {
			Available = className ~= nil,
			ClassName = className,
			Error = classError,
			UsesReplicatedClassAttribute = true,
		}
	end

	return Profile
end
