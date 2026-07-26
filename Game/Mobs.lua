return function(ctx)
	local Mobs = {}

	local GameContext = ctx:Require("GameContext")
	local Health = ctx:Require("Health")
	local cachedModule = nil

	local function resolve()
		if type(cachedModule) == "table" then
			return cachedModule
		end

		local moduleScript = GameContext.FindReplicated("Shared.Mobs")

		if not moduleScript or not moduleScript:IsA("ModuleScript") then
			return nil, "shared_mobs_not_found"
		end

		local ok, result = pcall(require, moduleScript)

		if not ok or type(result) ~= "table" then
			return nil, "shared_mobs_require_failed"
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
			return nil, "shared_mobs_missing_" .. string.lower(methodName)
		end

		local results = table.pack(pcall(method, module, ...))

		if not results[1] then
			return nil, "shared_mobs_call_failed_" .. string.lower(methodName)
		end

		return table.unpack(results, 2, results.n)
	end

	local function getTargetPart(mob)
		if not mob then
			return nil
		end

		return mob.PrimaryPart or mob:FindFirstChild("Collider") or mob:FindFirstChild("HumanoidRootPart")
	end

	local function getPropertyValue(properties, name)
		if typeof(properties) == "Instance" then
			local value = properties:FindFirstChild(name)
			return value and value.Value or nil
		elseif type(properties) == "table" then
			return properties[name]
		end

		return nil
	end

	local RANGED_NAME_HINTS = {
		"archer",
		"blossomtree",
		"cannon",
		"gunner",
		"mage",
		"ranger",
		"shooter",
		"slingshot",
		"sniper",
		"turret",
	}

	local RANGED_ATTACK_HINTS = {
		"arrow",
		"beam",
		"bullet",
		"laser",
		"missile",
		"projectile",
		"shoot",
		"spit",
	}

	local function containsHint(value, hints)
		local lowered = string.lower(tostring(value or ""))

		for _, hint in ipairs(hints) do
			if string.find(lowered, hint, 1, true) then
				return true
			end
		end

		return false
	end

	local function getRangedThreat(data, mob)
		local maximumRange = 0
		local projectileAttack = false
		local modelHint = containsHint(
			table.concat({
				tostring(mob and mob.Name or ""),
				tostring(data and data.Type or ""),
				tostring(data and data.NameTag or data and data.Name or ""),
			}, " "),
			RANGED_NAME_HINTS
		)
		local attacks = data and data.Attacks

		if type(attacks) == "table" then
			for attackName, attack in pairs(attacks) do
				if containsHint(attackName, RANGED_ATTACK_HINTS) then
					projectileAttack = true
				end

				if type(attack) == "table" then
					for field, value in pairs(attack) do
						local fieldName = string.lower(tostring(field))

						if containsHint(fieldName, RANGED_ATTACK_HINTS) and value ~= false and value ~= nil then
							projectileAttack = true
						end

						if
							type(value) == "number"
							and (
								string.find(fieldName, "attackdistance", 1, true)
								or string.find(fieldName, "maxdistance", 1, true)
								or string.find(fieldName, "range", 1, true)
								or string.find(fieldName, "shapedepth", 1, true)
							)
						then
							maximumRange = math.max(maximumRange, value)
						end
					end
				end
			end
		end

		for _, field in ipairs({ "AttackDistance", "AttackRange", "MaxDistance", "Range" }) do
			maximumRange = math.max(maximumRange, tonumber(data and data[field]) or 0)
		end

		local isRanged = modelHint or projectileAttack or maximumRange >= 28
		local score = maximumRange

		if projectileAttack then
			score = math.max(score, 60)
		end

		if modelHint then
			score = math.max(score, 80)
		end

		return isRanged, score
	end

	local function getNameTokens(filter)
		local tokens = {}

		for token in string.gmatch(string.lower(tostring(filter or "")), "[^,]+") do
			local cleaned = string.match(token, "^%s*(.-)%s*$")

			if cleaned and cleaned ~= "" then
				table.insert(tokens, cleaned)
			end
		end

		return tokens
	end

	local function nameMatches(descriptor, filter)
		local tokens = getNameTokens(filter)

		if #tokens == 0 then
			return true
		end

		local searchable = string.lower(table.concat({
			tostring(descriptor.ModelName or ""),
			tostring(descriptor.Type or ""),
			tostring(descriptor.NameTag or ""),
		}, " "))

		for _, token in ipairs(tokens) do
			if string.find(searchable, token, 1, true) then
				return true
			end
		end

		return false
	end

	local function exactNameMatches(descriptor, names)
		if type(names) ~= "table" or #names == 0 then
			return true
		end

		for _, allowed in ipairs(names) do
			if
				tostring(descriptor.ModelName) == tostring(allowed)
				or tostring(descriptor.Type) == tostring(allowed)
				or tostring(descriptor.NameTag) == tostring(allowed)
			then
				return true
			end
		end

		return false
	end

	local function getDirectHealth(mob)
		local properties = mob and mob:FindFirstChild("HealthProperties")
		local currentValue = properties and properties:FindFirstChild("Health")
		local maximumValue = properties and properties:FindFirstChild("MaxHealth")
		local barrierValue = properties and properties:FindFirstChild("BarrierHealth")
		local current = currentValue and tonumber(currentValue.Value)
		local maximum = maximumValue and tonumber(maximumValue.Value)
		local barrier = barrierValue and tonumber(barrierValue.Value) or 0

		if not current or not maximum or maximum <= 0 then
			return nil
		end

		return {
			Current = current,
			Maximum = maximum,
			Ratio = math.clamp(current / maximum, 0, 1),
			Barrier = math.max(barrier, 0),
			ProtectionRatio = math.clamp(
				(current + math.max(barrier, 0)) / maximum,
				0,
				1
			),
			Alive = current > 0,
		}
	end

	local function getWorkspaceMobs()
		local folder = workspace:FindFirstChild("Mobs")
		return folder and folder:GetChildren() or {}
	end

	function Mobs.GetAll()
		local all, allError = call("GetAllMobs")

		if type(all) ~= "table" then
			all = {}
		end

		-- Executors can require Shared.Mobs after a wave's MobCreated events
		-- have already fired. Its private client registry is then empty even
		-- though the replicated models, properties, colliders, and health are
		-- fully available in Workspace.Mobs. Merge both sources so late loader
		-- startup never makes an active wave invisible to automation.
		local seen = {}

		for _, mob in pairs(all) do
			seen[mob] = true
		end

		for _, mob in ipairs(getWorkspaceMobs()) do
			if
				not seen[mob]
				and mob:IsA("Model")
				and mob:FindFirstChild("MobProperties")
				and getTargetPart(mob)
			then
				seen[mob] = true
				table.insert(all, mob)
			end
		end

		if #all == 0 and allError then
			return all, allError
		end

		return all
	end

	function Mobs.GetTargetPart(mob)
		return getTargetPart(mob)
	end

	function Mobs.GetDescriptor(mob, origin)
		if typeof(mob) ~= "Instance" or not mob.Parent then
			return nil, "mob_unavailable"
		end

		local properties = mob:FindFirstChild("MobProperties")
		local mobType = getPropertyValue(properties, "MobType")
			or getPropertyValue(properties, "Type")
			or mob.Name
		local data, dataError = call("GetMobData", mob)

		if type(data) ~= "table" then
			data = call("GetMobDataByName", mobType)
		end

		if type(data) ~= "table" then
			data = {
				Type = mobType,
				Name = mob.Name,
				Level = getPropertyValue(properties, "Level"),
			}
		end

		local part = getTargetPart(mob)

		if not part then
			return nil, "mob_target_part_unavailable"
		end

		local health, healthError = Health.GetState(mob)

		if not health then
			health = getDirectHealth(mob)
		end

		if not health then
			return nil, healthError or "mob_health_unavailable"
		end

		local owner = call("GetOwner", mob)
		local bossTag = call("GetBossTag", mob)
		local elite = call("IsElite", mob)
		local hidden = call("IsHidden", mob)
		properties = data.Properties or properties
		local position = part.Position
		local distance = origin and (position - origin).Magnitude or nil
		local isRangedThreat, rangedThreatScore = getRangedThreat(data, mob)

		if owner == nil then
			owner = getPropertyValue(properties, "Owner")
		end

		if bossTag == nil then
			bossTag = getPropertyValue(properties, "BossTag")
				or data.BossTag
		end

		if elite == nil then
			elite = getPropertyValue(properties, "Elite") == true
		end

		if hidden == nil then
			hidden = getPropertyValue(properties, "Hidden") == true
		end

		return {
			Model = mob,
			ModelName = mob.Name,
			Type = data.Type or mobType,
			NameTag = data.NameTag or data.Name or mob.Name,
			Level = tonumber(data.Level or getPropertyValue(properties, "Level")) or 0,
			BossTag = bossTag,
			IsBoss = bossTag ~= nil and bossTag ~= false and bossTag ~= "",
			IsElite = elite == true,
			IsHidden = hidden == true,
			Invincible = data.Invincible == true,
			DoNotMove = data.DoNotMove == true,
			CannotTeleport = data.CannotTeleport == true or mob:FindFirstChild("CannotTeleport") ~= nil,
			Owner = owner,
			IsOwned = owner ~= nil,
			Position = position,
			Distance = distance,
			Health = health,
			Properties = properties,
			CurrentTarget = getPropertyValue(properties, "Target"),
			CurrentAttack = getPropertyValue(properties, "CurrentAttack"),
			IsRangedThreat = isRangedThreat,
			RangedThreatScore = rangedThreatScore,
			Data = data,
		}
	end

	function Mobs.IsValidTarget(descriptor, options)
		options = options or {}

		if
			not descriptor
			or not descriptor.Health
			or not descriptor.Health.Alive
			or descriptor.Invincible
			or descriptor.IsHidden
			or descriptor.Model:FindFirstChild("IgnorePlayerHits")
			or (options.ExcludedTargets and options.ExcludedTargets[descriptor.Model])
		then
			return false
		end

		if not options.IncludeOwned and descriptor.IsOwned then
			return false
		end

		if options.BossOnly and not descriptor.IsBoss then
			return false
		end

		if options.EliteOnly and not descriptor.IsElite then
			return false
		end

		if tonumber(options.Range) and descriptor.Distance and descriptor.Distance > tonumber(options.Range) then
			return false
		end

		return exactNameMatches(descriptor, options.ExactNames) and nameMatches(descriptor, options.NameFilter)
	end

	local function getDescriptorSafely(mob, origin)
		local ok, descriptor, descriptorError = pcall(Mobs.GetDescriptor, mob, origin)

		if not ok then
			return nil, "mob_descriptor_failed"
		end

		return descriptor, descriptorError
	end

	local function isBetter(candidate, current, mode, options)
		if not current then
			return true
		end

		if options.PrioritizeRangedThreats ~= false then
			if candidate.IsRangedThreat ~= current.IsRangedThreat then
				return candidate.IsRangedThreat
			end

			if
				candidate.IsRangedThreat
				and candidate.RangedThreatScore ~= current.RangedThreatScore
			then
				return (candidate.RangedThreatScore or 0) > (current.RangedThreatScore or 0)
			end
		end

		if mode == "Lowest Health" then
			if candidate.Health.Ratio ~= current.Health.Ratio then
				return candidate.Health.Ratio < current.Health.Ratio
			end
		elseif mode == "Highest Level" then
			if candidate.Level ~= current.Level then
				return candidate.Level > current.Level
			end
		elseif mode == "Boss Priority" then
			if candidate.IsBoss ~= current.IsBoss then
				return candidate.IsBoss
			end
		elseif mode == "Crowd Priority" then
			if candidate.ClusterCount ~= current.ClusterCount then
				return (candidate.ClusterCount or 1) > (current.ClusterCount or 1)
			end

			if candidate.IsBoss ~= current.IsBoss then
				return candidate.IsBoss
			end
		end

		return (candidate.Distance or math.huge) < (current.Distance or math.huge)
	end

	function Mobs.SelectTarget(options)
		options = options or {}
		local root = GameContext.GetRootPart()

		if not root then
			return nil, "character_root_unavailable"
		end

		local all, allError = Mobs.GetAll()

		if not all then
			return nil, allError
		end

		local selected = nil
		local mode = options.Mode or "Nearest"
		local selectionOrigin = typeof(options.OriginPosition) == "Vector3" and options.OriginPosition or root.Position
		local candidates = {}

		for _, mob in pairs(all) do
			local descriptor = getDescriptorSafely(mob, selectionOrigin)

			if Mobs.IsValidTarget(descriptor, options) then
				table.insert(candidates, descriptor)
			end
		end

		if mode == "Crowd Priority" then
			local clusterRadius = math.max(1, tonumber(options.ClusterRadius) or 24)

			for _, candidate in ipairs(candidates) do
				local clusterCount = 0

				for _, nearby in ipairs(candidates) do
					if (candidate.Position - nearby.Position).Magnitude <= clusterRadius then
						clusterCount = clusterCount + 1
					end
				end

				candidate.ClusterCount = clusterCount
			end
		end

		for _, candidate in ipairs(candidates) do
			if isBetter(candidate, selected, mode, options) then
				selected = candidate
			end
		end

		if not selected then
			return nil, "no_matching_mob"
		end

		return selected.Model, selected
	end

	function Mobs.GetMatching(options)
		options = options or {}
		local root = GameContext.GetRootPart()

		if not root then
			return nil, "character_root_unavailable"
		end

		local all, allError = Mobs.GetAll()

		if not all then
			return nil, allError
		end

		local matching = {}
		local selectionOrigin = typeof(options.OriginPosition) == "Vector3" and options.OriginPosition or root.Position

		for _, mob in pairs(all) do
			local descriptor = getDescriptorSafely(mob, selectionOrigin)

			if Mobs.IsValidTarget(descriptor, options) then
				table.insert(matching, descriptor)
			end
		end

		return matching
	end

	function Mobs.GetOwnedSummary(owner)
		owner = owner or GameContext.GetLocalPlayer()
		local ownerCharacter = typeof(owner) == "Instance" and owner:IsA("Player") and owner.Character or nil
		local all, allError = Mobs.GetAll()

		if not all then
			return nil, allError
		end

		local summary = {
			Total = 0,
			Weak = 0,
			Strong = 0,
			Other = 0,
			Mobs = {},
		}

		for _, mob in pairs(all) do
			local descriptor = getDescriptorSafely(mob)

			if
				descriptor
				and descriptor.Health.Alive
				and descriptor.IsOwned
				and (descriptor.Owner == owner or descriptor.Owner == ownerCharacter)
			then
				local mobType = string.lower(tostring(descriptor.Type))
				summary.Total = summary.Total + 1
				table.insert(summary.Mobs, descriptor)

				if string.find(mobType, "summonersummonweak", 1, true) then
					summary.Weak = summary.Weak + 1
				elseif string.find(mobType, "summonersummonstrong", 1, true) then
					summary.Strong = summary.Strong + 1
				else
					summary.Other = summary.Other + 1
				end
			end
		end

		return summary
	end

	function Mobs.CountOwnedNear(owner, target, radius, summonKind)
		local summary, summaryError = Mobs.GetOwnedSummary(owner)

		if not summary then
			return nil, summaryError
		end

		local targetPart = getTargetPart(target)

		if not targetPart then
			return nil, "target_part_unavailable"
		end

		local kind = string.lower(tostring(summonKind or ""))
		local count = 0

		for _, descriptor in ipairs(summary.Mobs) do
			local typeName = string.lower(tostring(descriptor.Type))
			local kindMatches = kind == ""
				or (kind == "weak" and string.find(typeName, "weak", 1, true))
				or (kind == "strong" and string.find(typeName, "strong", 1, true))

			if kindMatches and (descriptor.Position - targetPart.Position).Magnitude <= (tonumber(radius) or 25) then
				count = count + 1
			end
		end

		return count
	end

	function Mobs.GetThreatState(radius)
		local root = GameContext.GetRootPart()
		local character = GameContext.GetCharacter()
		local player = GameContext.GetLocalPlayer()

		if not root or not character then
			return nil, "character_unavailable"
		end

		local all, allError = Mobs.GetAll()

		if not all then
			return nil, allError
		end

		local state = {
			Count = 0,
			BossCount = 0,
			AttackingCount = 0,
			Nearest = nil,
			NearestDistance = math.huge,
			Attacking = {},
			NearestAttacking = nil,
			NearestAttackingDistance = math.huge,
		}

		for _, mob in pairs(all) do
			local descriptor = getDescriptorSafely(mob, root.Position)

			if
				Mobs.IsValidTarget(descriptor, {
					Range = tonumber(radius) or 30,
					IncludeOwned = false,
				})
				and (
					descriptor.CurrentTarget == character
					or descriptor.CurrentTarget == player
				)
			then
				state.Count = state.Count + 1

				if descriptor.IsBoss then
					state.BossCount = state.BossCount + 1
				end

				if type(descriptor.CurrentAttack) == "string" and descriptor.CurrentAttack ~= "" then
					state.AttackingCount = state.AttackingCount + 1
					table.insert(state.Attacking, descriptor)

					if descriptor.Distance < state.NearestAttackingDistance then
						state.NearestAttacking = descriptor
						state.NearestAttackingDistance = descriptor.Distance
					end
				end

				if descriptor.Distance < state.NearestDistance then
					state.Nearest = descriptor
					state.NearestDistance = descriptor.Distance
				end
			end
		end

		return state
	end

	function Mobs.Describe()
		local module, resolveError = resolve()

		return {
			Available = module ~= nil,
			Error = resolveError,
			HasLocalMobList = module and type(module.GetAllMobs) == "function" or false,
			HasMobData = module and type(module.GetMobData) == "function" or false,
			HasBossTags = module and type(module.GetBossTag) == "function" or false,
			HasEliteState = module and type(module.IsElite) == "function" or false,
			HasOwnership = module and type(module.GetOwner) == "function" or false,
		}
	end

	return Mobs
end
