return function(ctx)
	local ClassRegistry = {}

	local Profile = ctx:Require("Profile")

	local REGISTRY = {
		Archer = {
			AdapterKey = "Archer",
			FeatureKey = "ArcherFeature",
		},
		Swordmaster = {
			AdapterKey = "Swordmaster",
			FeatureKey = "SwordmasterFeature",
		},
	}

	function ClassRegistry.GetCurrentClass()
		return Profile.GetCurrentClass()
	end

	function ClassRegistry.GetDefinition(className)
		return REGISTRY[className]
	end

	function ClassRegistry.IsVerified(className)
		return REGISTRY[className] ~= nil
	end

	function ClassRegistry.GetCurrentAdapter()
		local className, classError = ClassRegistry.GetCurrentClass()

		if not className then
			return nil, classError
		end

		local definition = REGISTRY[className]

		if not definition then
			return nil, "class_source_not_received:" .. tostring(className)
		end

		return ctx:Require(definition.AdapterKey)
	end

	function ClassRegistry.GetCurrentFeature()
		local className, classError = ClassRegistry.GetCurrentClass()

		if not className then
			return nil, classError
		end

		local definition = REGISTRY[className]

		if not definition then
			return nil, "class_source_not_received:" .. tostring(className)
		end

		return ctx:Require(definition.FeatureKey)
	end

	function ClassRegistry.Observe(callback)
		return Profile.ObserveClass(callback)
	end

	function ClassRegistry.Describe()
		local className, classError = ClassRegistry.GetCurrentClass()

		return {
			ClassName = className,
			Error = classError,
			Verified = className ~= nil and ClassRegistry.IsVerified(className),
			Definition = className and REGISTRY[className] or nil,
		}
	end

	return ClassRegistry
end
