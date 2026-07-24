return function(ctx)
	local Skills = {}

	local GameContext = ctx:Require("GameContext")
	local Profile = ctx:Require("Profile")
	local cachedSkills = nil

	local SLOT_ORDER = {
		"Primary",
		"Skill1",
		"Skill2",
		"Skill3",
		"Skill4",
		"Ultimate",
		"Dodge",
		"Sheath",
		"SwapPerk",
	}

	local function requireReplicated(path, expectedName)
		local moduleScript = GameContext.FindReplicated(path)

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, expectedName .. "_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, expectedName .. "_require_failed"
		end

		return result
	end

	local function resolveSkills()
		if cachedSkills then
			return cachedSkills
		end

		local result, resolveError = requireReplicated("Shared.Skills", "shared_skills")

		if not result then
			return nil, resolveError
		end

		cachedSkills = result
		return cachedSkills
	end

	function Skills.GetCurrentClass()
		return Profile.GetCurrentClass()
	end

	function Skills.GetClassSkills(className)
		local catalog, catalogError = resolveSkills()

		if not catalog then
			return nil, catalogError
		end

		local classSkills = catalog[className]

		if type(classSkills) ~= "table" then
			return nil, "class_skills_not_found:" .. tostring(className)
		end

		return classSkills
	end

	function Skills.List(className)
		className = className or Skills.GetCurrentClass()

		if not className then
			return {}
		end

		local classSkills = Skills.GetClassSkills(className)

		if not classSkills then
			return {}
		end

		local result = {}
		local seen = {}

		local function addSlot(slot)
			local metadata = classSkills[slot]

			if type(metadata) ~= "table" then
				return
			end

			seen[slot] = true
			table.insert(result, {
				Slot = slot,
				Name = metadata.Name or slot,
				FunctionName = metadata.FunctionName,
				Cooldown = metadata.Cooldown,
				Icon = metadata.Icon,
			})
		end

		for _, slot in ipairs(SLOT_ORDER) do
			addSlot(slot)
		end

		local extraSlots = {}

		for slot, metadata in pairs(classSkills) do
			if type(metadata) == "table" and not seen[slot] then
				table.insert(extraSlots, slot)
			end
		end

		table.sort(extraSlots)

		for _, slot in ipairs(extraSlots) do
			addSlot(slot)
		end

		return result
	end

	function Skills.Describe()
		local catalog, catalogError = resolveSkills()

		if not catalog then
			return {
				Available = false,
				Error = catalogError,
				Options = {},
			}
		end

		local className, classError = Skills.GetCurrentClass()

		if not className then
			return {
				Available = true,
				Error = classError,
				Options = {},
			}
		end

		local options = Skills.List(className)

		return {
			Available = true,
			ClassName = className,
			ClassAvailable = #options > 0,
			Options = options,
		}
	end

	return Skills
end
