-- World Zero source exporter
--
-- Run this inside the game with an executor that provides decompile(),
-- writefile(), and makefolder(). Files are written relative to the
-- executor's workspace directory.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local env = getgenv()

local DEFAULT_MODULE_PATHS = {
	"ReplicatedStorage.Shared.AuraChest",
	"ReplicatedStorage.Shared.Drops",
	"ReplicatedStorage.Shared.Inventory",
	"ReplicatedStorage.Shared.ItemAbilities",
	"ReplicatedStorage.Shared.ItemDrops",
	"ReplicatedStorage.Shared.Items",
	"ReplicatedStorage.Shared.WorldEvents",
	"ReplicatedStorage.Shared.Gamebeast.Infra.Shared.Modules.GetRemote",

	"ReplicatedStorage.Client.Gui.GuiScripts.AuraChest",
	"ReplicatedStorage.Client.Gui.GuiScripts.HubTeleport",
	"ReplicatedStorage.Client.Gui.GuiScripts.Inventory",
	"ReplicatedStorage.Client.Gui.GuiScripts.LootReceived",
	"ReplicatedStorage.Client.Gui.GuiScripts.MissionObjective",
	"ReplicatedStorage.Client.Gui.GuiScripts.MissionQueue",
	"ReplicatedStorage.Client.Gui.GuiScripts.MissionRewards",
	"ReplicatedStorage.Client.Gui.GuiScripts.MissionSelect",
	"ReplicatedStorage.Client.Gui.GuiScripts.QuestList",
	"ReplicatedStorage.Client.Gui.GuiScripts.Rewards",
	"ReplicatedStorage.Client.Gui.GuiScripts.WorldTeleport",
	"ReplicatedStorage.Client.TutorialDungeon",
}

local DEFAULT_TREE_PATHS = {
	"ReplicatedStorage.Shared.Status.Statuses",
	"ReplicatedStorage.Shared.Chests",
	"ReplicatedStorage.Shared.Gear",
	"ReplicatedStorage.Shared.Missions",
	"ReplicatedStorage.Shared.Objectives",
	"ReplicatedStorage.Shared.Quests",
	"ReplicatedStorage.Shared.Settings",
	"ReplicatedStorage.Shared.Teleport",

	"ReplicatedStorage.Client.Gui.GuiScripts.EventDungeonFinish",
	"ReplicatedStorage.Client.Gui.GuiScripts.QuestTracker",
}

local config = env.WorldZeroSourceExporter or {}
local outputBase = tostring(config.OutputRoot or "WorldZeroSourceDump")
local fullReplicatedStorage = config.FullReplicatedStorage ~= false
local runId =
	tostring(config.RunId or (fullReplicatedStorage and ("replicated-storage-" .. tostring(game.PlaceId)) or os.time()))
local outputRoot = outputBase .. "/" .. runId
local sourceRoot = outputRoot .. "/sources"
local modulePaths = config.ModulePaths or DEFAULT_MODULE_PATHS
local treePaths = config.TreePaths or DEFAULT_TREE_PATHS
local childTimeout = tonumber(config.ChildTimeout) or 3
local yieldEvery = math.max(tonumber(config.YieldEvery) or 10, 1)
local includeMetadata = config.IncludeMetadata ~= false
local copiedOutputPath = config.CopyOutputPath ~= false
local resume = config.Resume ~= false
local overwrite = config.Overwrite == true
local checkpointEvery = math.max(tonumber(config.CheckpointEvery) or 25, 1)

if type(modulePaths) ~= "table" then
	modulePaths = DEFAULT_MODULE_PATHS
end

if type(treePaths) ~= "table" then
	treePaths = DEFAULT_TREE_PATHS
end

local function getCapability(name)
	local value = env[name]

	if typeof(value) == "function" then
		return value
	end

	return nil
end

local writeFile = getCapability("writefile") or writefile
local makeFolder = getCapability("makefolder") or makefolder
local isFolder = getCapability("isfolder") or isfolder
local isFile = getCapability("isfile") or isfile
local setClipboard = getCapability("setclipboard") or setclipboard
local decompiler = getCapability("decompile") or decompile

if typeof(decompiler) ~= "function" and syn then
	decompiler = syn.decompile
end

assert(typeof(writeFile) == "function", "[WorldZeroSourceExporter] writefile() is unavailable")
assert(typeof(makeFolder) == "function", "[WorldZeroSourceExporter] makefolder() is unavailable")
assert(typeof(decompiler) == "function", "[WorldZeroSourceExporter] decompile() is unavailable")

local createdFolders = {}

local function folderExists(path)
	if createdFolders[path] then
		return true
	end

	if typeof(isFolder) == "function" then
		local ok, result = pcall(isFolder, path)

		if ok and result == true then
			createdFolders[path] = true
			return true
		end
	end

	return false
end

local function ensureFolder(path)
	local current = ""

	for segment in string.gmatch(path, "[^/]+") do
		current = current == "" and segment or (current .. "/" .. segment)

		if not folderExists(current) then
			local ok, folderError = pcall(makeFolder, current)

			if not ok and not folderExists(current) then
				error("[WorldZeroSourceExporter] Could not create " .. current .. ": " .. tostring(folderError), 0)
			end

			createdFolders[current] = true
		end
	end
end

local function sanitizeSegment(value)
	local cleaned = string.gsub(tostring(value), '[<>:"/\\|%?%*%c]', "_")

	if cleaned == "" then
		return "_"
	end

	return cleaned
end

local function splitPath(path)
	local result = {}

	for segment in string.gmatch(path, "[^%.]+") do
		table.insert(result, segment)
	end

	return result
end

local function resolvePath(path)
	local segments = splitPath(path)

	if #segments == 0 then
		return nil, "empty_path"
	end

	local serviceOk, current = pcall(game.GetService, game, segments[1])

	if not serviceOk or not current then
		return nil, "service_not_found:" .. tostring(segments[1])
	end

	for index = 2, #segments do
		local name = segments[index]
		local child = current:FindFirstChild(name)

		if not child then
			local waitOk, waited = pcall(current.WaitForChild, current, name, childTimeout)

			if waitOk then
				child = waited
			end
		end

		if not child then
			return nil, "child_not_found:" .. tostring(name)
		end

		current = child
	end

	return current
end

local function isScript(instance)
	return instance and (instance:IsA("ModuleScript") or instance:IsA("LocalScript") or instance:IsA("Script"))
end

local function getOutputPath(instance)
	local segments = splitPath(instance:GetFullName())

	for index, segment in ipairs(segments) do
		segments[index] = sanitizeSegment(segment)
	end

	return sourceRoot .. "/" .. table.concat(segments, "/") .. ".lua"
end

local function writeText(path, text)
	local parent = string.match(path, "^(.*)/[^/]+$")

	if parent then
		ensureFolder(parent)
	end

	local ok, writeError = pcall(writeFile, path, text)

	if not ok then
		return false, tostring(writeError)
	end

	return true
end

local function fileExists(path)
	if typeof(isFile) ~= "function" then
		return false
	end

	local ok, result = pcall(isFile, path)
	return ok and result == true
end

local queue = {}
local seenInstances = {}
local discoveryRecords = {}
local claimedOutputPaths = {}

local function addScript(instance, requestedPath, requestKind)
	if not isScript(instance) or seenInstances[instance] then
		return
	end

	seenInstances[instance] = true
	table.insert(queue, {
		Instance = instance,
		RequestedPath = requestedPath,
		RequestKind = requestKind,
	})
end

local function discoverModule(path)
	local instance, resolveError = resolvePath(path)

	if not instance then
		table.insert(discoveryRecords, {
			Path = path,
			Kind = "module",
			Ok = false,
			Error = resolveError,
		})
		return
	end

	if not isScript(instance) then
		table.insert(discoveryRecords, {
			Path = path,
			Kind = "module",
			Ok = false,
			Error = "resolved_instance_is_not_script:" .. instance.ClassName,
		})
		return
	end

	addScript(instance, path, "module")
	table.insert(discoveryRecords, {
		Path = path,
		Kind = "module",
		Ok = true,
		Resolved = instance:GetFullName(),
	})
end

local function discoverTree(path)
	local root, resolveError = resolvePath(path)

	if not root then
		table.insert(discoveryRecords, {
			Path = path,
			Kind = "tree",
			Ok = false,
			Error = resolveError,
		})
		return
	end

	local count = 0

	if isScript(root) then
		addScript(root, path, "tree")
		count = count + 1
	end

	for _, descendant in ipairs(root:GetDescendants()) do
		if isScript(descendant) then
			addScript(descendant, path, "tree")
			count = count + 1
		end
	end

	table.insert(discoveryRecords, {
		Path = path,
		Kind = "tree",
		Ok = true,
		Resolved = root:GetFullName(),
		ScriptCount = count,
	})
end

local function getRemoteInventory()
	local lines = {}

	for _, instance in ipairs(ReplicatedStorage:GetDescendants()) do
		local className = instance.ClassName

		if className == "RemoteEvent" or className == "RemoteFunction" or className == "UnreliableRemoteEvent" then
			table.insert(lines, className .. "\t" .. instance:GetFullName())
		end
	end

	table.sort(lines)
	return lines
end

local function getWorldCandidates()
	local lines = {}
	local patterns = {
		"chest",
		"drop",
		"enemy",
		"loot",
		"mission",
		"mob",
		"objective",
		"pickup",
		"quest",
	}

	for _, instance in ipairs(workspace:GetDescendants()) do
		local lowered = string.lower(instance.Name)
		local matched = false

		for _, pattern in ipairs(patterns) do
			if string.find(lowered, pattern, 1, true) then
				matched = true
				break
			end
		end

		if matched then
			table.insert(lines, instance.ClassName .. "\t" .. instance:GetFullName())
		end
	end

	table.sort(lines)
	return lines
end

local function runExporter()
	print("")
	print("[WorldZeroSourceExporter] ========== EXPORT START ==========")
	ensureFolder(sourceRoot)

	if fullReplicatedStorage then
		discoverTree("ReplicatedStorage")
	else
		for _, path in ipairs(modulePaths) do
			discoverModule(path)
		end

		for _, path in ipairs(treePaths) do
			discoverTree(path)
		end
	end

	table.sort(queue, function(a, b)
		return a.Instance:GetFullName() < b.Instance:GetFullName()
	end)

	local exports = {}
	local succeeded = 0
	local skipped = 0

	local function writeCheckpoint(processed)
		local checkpoint = {
			Exporter = "World Zero SourceExporter",
			Version = 2,
			GeneratedAt = os.time(),
			PlaceId = game.PlaceId,
			GameId = game.GameId,
			OutputRoot = outputRoot,
			FullReplicatedStorage = fullReplicatedStorage,
			Summary = {
				Discovered = #queue,
				Processed = processed,
				Succeeded = succeeded,
				SkippedExisting = skipped,
				Failed = processed - succeeded,
			},
			Exports = exports,
		}
		local encodeOk, encoded = pcall(HttpService.JSONEncode, HttpService, checkpoint)

		if encodeOk then
			writeText(outputRoot .. "/checkpoint.json", encoded)
		end

		writeText(
			outputRoot .. "/PROGRESS.txt",
			table.concat({
				"World Zero SourceExporter progress",
				"Output: " .. outputRoot,
				"Discovered: " .. tostring(#queue),
				"Processed: " .. tostring(processed),
				"Succeeded: " .. tostring(succeeded),
				"Skipped existing: " .. tostring(skipped),
				"Failed: " .. tostring(processed - succeeded),
			}, "\n")
		)
	end

	for index, item in ipairs(queue) do
		local instance = item.Instance
		local fullName = instance:GetFullName()
		local outputPath = getOutputPath(instance)
		local collisionIndex = claimedOutputPaths[outputPath] or 0

		claimedOutputPaths[outputPath] = collisionIndex + 1

		if collisionIndex > 0 then
			outputPath = string.gsub(outputPath, "%.lua$", "__duplicate_" .. tostring(collisionIndex + 1) .. ".lua")
		end

		local record = {
			Index = index,
			RequestedPath = item.RequestedPath,
			RequestKind = item.RequestKind,
			FullName = fullName,
			ClassName = instance.ClassName,
			OutputFile = outputPath,
			Ok = false,
		}

		if resume and not overwrite and fileExists(outputPath) then
			record.Ok = true
			record.SkippedExisting = true
			succeeded = succeeded + 1
			skipped = skipped + 1
		else
			local decompileOk, source = pcall(decompiler, instance)

			if decompileOk and type(source) == "string" and source ~= "" then
				local header = "-- Exported by World Zero SourceExporter\n"
					.. "-- Full Name: "
					.. fullName
					.. "\n"
					.. "-- Class: "
					.. instance.ClassName
					.. "\n\n"
				local writeOk, writeError = writeText(outputPath, header .. source)

				if writeOk then
					record.Ok = true
					succeeded = succeeded + 1
					print(
						"[WorldZeroSourceExporter] [" .. tostring(index) .. "/" .. tostring(#queue) .. "] " .. fullName
					)
				else
					record.Error = "write_failed:" .. tostring(writeError)
					warn("[WorldZeroSourceExporter] Write failed:", fullName, writeError)
				end
			else
				record.Error = decompileOk and "decompiler_returned_no_source"
					or ("decompile_failed:" .. tostring(source))
				warn("[WorldZeroSourceExporter] Decompile failed:", fullName, record.Error)
			end
		end

		table.insert(exports, record)

		if index % checkpointEvery == 0 then
			writeCheckpoint(index)
		end

		if index % yieldEvery == 0 then
			task.wait()
		end
	end

	writeCheckpoint(#queue)

	local manifest = {
		Exporter = "World Zero SourceExporter",
		Version = 2,
		GeneratedAt = os.time(),
		PlaceId = game.PlaceId,
		GameId = game.GameId,
		OutputRoot = outputRoot,
		FullReplicatedStorage = fullReplicatedStorage,
		Resume = resume,
		Overwrite = overwrite,
		RequestedModules = modulePaths,
		RequestedTrees = treePaths,
		Discovery = discoveryRecords,
		Exports = exports,
		Summary = {
			Discovered = #queue,
			Succeeded = succeeded,
			SkippedExisting = skipped,
			Failed = #queue - succeeded,
		},
	}

	if includeMetadata then
		local remoteLines = getRemoteInventory()
		local worldLines = getWorldCandidates()

		writeText(outputRoot .. "/metadata/ReplicatedRemotes.txt", table.concat(remoteLines, "\n"))
		writeText(outputRoot .. "/metadata/WorldCandidates.txt", table.concat(worldLines, "\n"))
		manifest.Metadata = {
			RemoteCount = #remoteLines,
			WorldCandidateCount = #worldLines,
		}
	end

	local manifestOk, encodedManifest = pcall(HttpService.JSONEncode, HttpService, manifest)

	if manifestOk then
		writeText(outputRoot .. "/manifest.json", encodedManifest)
	end

	local failureLines = {}

	for _, record in ipairs(exports) do
		if not record.Ok then
			table.insert(
				failureLines,
				table.concat({
					tostring(record.ClassName),
					tostring(record.FullName),
					tostring(record.Error),
				}, "\t")
			)
		end
	end

	writeText(outputRoot .. "/metadata/Failures.txt", table.concat(failureLines, "\n"))

	local summary = table.concat({
		"World Zero SourceExporter",
		"Output: " .. outputRoot,
		"Discovered: " .. tostring(#queue),
		"Succeeded: " .. tostring(succeeded),
		"Skipped existing: " .. tostring(skipped),
		"Failed: " .. tostring(#queue - succeeded),
		"PlaceId: " .. tostring(game.PlaceId),
		"GameId: " .. tostring(game.GameId),
	}, "\n")

	writeText(outputRoot .. "/SUMMARY.txt", summary)
	writeText(outputBase .. "/LATEST.txt", outputRoot)

	if copiedOutputPath and typeof(setClipboard) == "function" then
		pcall(setClipboard, outputRoot)
	end

	print("[WorldZeroSourceExporter] " .. summary:gsub("\n", " | "))
	print("[WorldZeroSourceExporter] =========== EXPORT END ===========")
	print("")

	return manifest
end

return runExporter()
