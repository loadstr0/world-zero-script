return function(ctx)
	local ClassRegistry = {}

	local Profile = ctx:Require("Profile")

	local REGISTRY = {
		Assassin = {
			AdapterKey = "Assassin",
			FeatureKey = "AssassinFeature",
		},
		Archer = {
			AdapterKey = "Archer",
			FeatureKey = "ArcherFeature",
		},
		Berserker = {
			AdapterKey = "Berserker",
			FeatureKey = "BerserkerFeature",
		},
		Defender = {
			AdapterKey = "Defender",
			FeatureKey = "DefenderFeature",
		},
		Demon = {
			AdapterKey = "Demon",
			FeatureKey = "DemonFeature",
		},
		Dragoon = {
			AdapterKey = "Dragoon",
			FeatureKey = "DragoonFeature",
		},
		DualWielder = {
			AdapterKey = "DualWielder",
			FeatureKey = "DualWielderFeature",
		},
		Greatsword = {
			AdapterKey = "Greatsword",
			FeatureKey = "GreatswordFeature",
			AutomationReady = false,
		},
		Guardian = {
			AdapterKey = "Guardian",
			FeatureKey = "GuardianFeature",
		},
		Hunter = {
			AdapterKey = "Hunter",
			FeatureKey = "HunterFeature",
		},
		IcefireMage = {
			AdapterKey = "IcefireMage",
			FeatureKey = "IcefireMageFeature",
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
		local definition = className and REGISTRY[className] or nil

		return {
			ClassName = className,
			Error = classError,
			Verified = definition ~= nil,
			AutomationReady = definition ~= nil and definition.AutomationReady ~= false,
			Definition = definition,
		}
	end

	return ClassRegistry
end
