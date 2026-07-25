return function(ctx)
	local Pets = {}

	local GameContext = ctx:Require("GameContext")
	local Players = ctx.Services.Players
	local modules = {}
	local lastAttemptAt = 0
	local cooldownUntil = 0
	local signalConnection = nil

	local function resolve(path, key)
		if type(modules[key]) == "table" then
			return modules[key]
		end

		local moduleScript = GameContext.FindReplicated(path)

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "module_not_found:" .. path
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "module_require_failed:" .. path .. ":" .. tostring(result)
		end

		modules[key] = result
		return result
	end

	local function getModules()
		local profile, profileError = resolve("Shared.Profile", "Profile")

		if not profile then
			return nil, profileError
		end

		local pets, petsError = resolve("Shared.Pets", "Pets")

		if not pets then
			return nil, petsError
		end

		local petSkills, petSkillsError = resolve("Shared.PetSkills", "PetSkills")

		if not petSkills then
			return nil, petSkillsError
		end

		local items, itemsError = resolve("Shared.Items", "Items")

		if not items then
			return nil, itemsError
		end

		return {
			Profile = profile,
			Pets = pets,
			PetSkills = petSkills,
			Items = items,
		}
	end

	local function getEquipped(modulesResolved)
		local player = Players.LocalPlayer

		if not player then
			return nil, nil, "local_player_unavailable"
		end

		local ok, equips = pcall(
			modulesResolved.Profile.GetPlayerEquips,
			modulesResolved.Profile,
			player
		)

		if not ok or typeof(equips) ~= "Instance" then
			return nil, player, "player_equips_unavailable"
		end

		local slot = equips:FindFirstChild("Pet")
		local item = slot and slot:GetChildren()[1]

		if not item then
			return nil, player, "pet_not_equipped"
		end

		return item, player
	end

	local function ensureCooldownSignal(petSkills)
		if signalConnection or type(petSkills.GetPetSkillUsedSignal) ~= "function" then
			return
		end

		local ok, signal = pcall(petSkills.GetPetSkillUsedSignal, petSkills)

		if not ok or type(signal) ~= "table" then
			return
		end

		local connect = signal.Connect or signal.connect

		if type(connect) ~= "function" then
			return
		end

		local connected, connection = pcall(connect, signal, function(cooldown)
			cooldownUntil = os.clock() + math.max(0, tonumber(cooldown) or 0)
		end)

		if connected then
			signalConnection = connection
		end
	end

	function Pets.GetStatus()
		local resolved, resolveError = getModules()

		if not resolved then
			return {
				Available = false,
				Error = resolveError,
			}
		end

		local item, player, equippedError = getEquipped(resolved)

		if not item then
			return {
				Available = true,
				Equipped = false,
				Error = equippedError,
			}
		end

		local definition = resolved.Items[item.Name]
		local itemType = type(definition) == "table" and definition.Type or nil
		local skillOk, skillName =
			pcall(resolved.Pets.GetPetSkillFromPetRef, resolved.Pets, item)
		local skillData = nil

		if skillOk and type(skillName) == "string" and type(resolved.PetSkills.GetSkillData) == "function" then
			local dataOk, data =
				pcall(resolved.PetSkills.GetSkillData, resolved.PetSkills, skillName)

			if dataOk and type(data) == "table" then
				skillData = data
			end
		end

		local lockedOk, locked =
			pcall(resolved.Pets.IsPetAbilityLocked, resolved.Pets, player)

		return {
			Available = true,
			Equipped = true,
			Item = item,
			Name = item.Name,
			Type = itemType,
			IsEgg = itemType == "Egg",
			SkillName = skillOk and skillName or nil,
			Skill = skillData,
			Cooldown = skillData and tonumber(skillData.Cooldown) or nil,
			NeedsTarget = skillData and skillData.NeedsTarget == true or false,
			Locked = lockedOk and locked == true or false,
			Error = not skillOk and tostring(skillName) or nil,
		}
	end

	function Pets.UseSkill(target)
		local now = os.clock()

		if now - lastAttemptAt < 0.2 then
			return false, "pet_skill_attempt_throttled"
		elseif now < cooldownUntil then
			return false, "pet_skill_on_cooldown"
		end

		local resolved, resolveError = getModules()

		if not resolved then
			return false, resolveError
		end

		local status = Pets.GetStatus()

		if not status.Equipped then
			return false, status.Error or "pet_not_equipped"
		elseif status.IsEgg then
			return false, "equipped_item_is_egg"
		elseif not status.SkillName then
			return false, "pet_has_no_active_skill"
		elseif status.Locked then
			return false, "pet_ability_locked"
		elseif status.NeedsTarget and typeof(target) ~= "Instance" then
			return false, "pet_skill_needs_target"
		end

		ensureCooldownSignal(resolved.PetSkills)
		lastAttemptAt = now

		local ok, useError = pcall(
			resolved.PetSkills.UseSkill,
			resolved.PetSkills,
			Players.LocalPlayer,
			target,
			nil
		)

		if not ok then
			return false, "pet_skill_failed:" .. tostring(useError)
		end

		return true
	end

	function Pets.Describe()
		local status = Pets.GetStatus()

		return {
			Available = status.Available,
			Error = status.Error,
			EquippedName = status.Name,
			EquippedType = status.Type,
			ActiveSkill = status.SkillName,
			Locked = status.Locked,
			SupportsAutoSkill = status.Available == true,
		}
	end

	return Pets
end
