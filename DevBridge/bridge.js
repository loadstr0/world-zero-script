#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const childProcess = require("child_process");

const APP_DIR = __dirname;
const PROJECT_DIR = path.resolve(APP_DIR, "..");
const LOCAL_APP_DATA = process.env.LOCALAPPDATA || path.join(process.env.USERPROFILE || "", "AppData", "Local");
const REAL_DIR = process.env.WZ_REAL_DIR || path.join(LOCAL_APP_DATA, "Real");
const IPC_DIR = process.env.WZ_REAL_IPC || path.join(REAL_DIR, "ipc");
const REAL_WORKSPACE = process.env.WZ_REAL_WORKSPACE || path.join(REAL_DIR, "workspace");
const REMOTE_RESULT_DIR = path.join(REAL_WORKSPACE, "WorldZeroDevBridge", "results");
const LOCAL_RESULT_DIR = path.join(APP_DIR, "results");
const PROBE_DIR = path.join(APP_DIR, "probes");

function ensureDirectory(directory) {
	fs.mkdirSync(directory, { recursive: true });
}

function readText(filePath) {
	return fs.readFileSync(filePath, "utf8");
}

function writeText(filePath, content) {
	ensureDirectory(path.dirname(filePath));
	fs.writeFileSync(filePath, content, "utf8");
}

function writeJson(filePath, value) {
	writeText(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function activeInstanceDirectories() {
	ensureDirectory(IPC_DIR);

	return fs
		.readdirSync(IPC_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory() && /^\d+$/.test(entry.name))
		.map((entry) => path.join(IPC_DIR, entry.name));
}

function getOption(argumentsList, name, fallback) {
	const index = argumentsList.indexOf(name);

	if (index < 0) {
		return fallback;
	}

	const value = argumentsList[index + 1];

	if (!value || value.startsWith("--")) {
		throw new Error(`${name} requires a value`);
	}

	argumentsList.splice(index, 2);
	return value;
}

function takeFlag(argumentsList, name) {
	const index = argumentsList.indexOf(name);

	if (index < 0) {
		return false;
	}

	argumentsList.splice(index, 1);
	return true;
}

function makeJobId() {
	const time = Date.now().toString(36);
	const random = crypto.randomBytes(6).toString("hex");
	return `${time}-${random}`;
}

function luaLongString(content) {
	for (let depth = 1; depth <= 10; depth += 1) {
		const equals = "=".repeat(depth);
		const closing = `]${equals}]`;

		if (!content.includes(closing)) {
			return `[${equals}[${content}]${equals}]`;
		}
	}

	throw new Error("Could not encode source as a Luau long string");
}

function buildWrappedSource(source, job) {
	const encodedSource = luaLongString(source);
	const encodedJobId = JSON.stringify(job.id);

	return `-- World Zero DevBridge job ${job.id}
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local jobId = ${encodedJobId}
local source = ${encodedSource}
local resultRoot = "WorldZeroDevBridge"
local resultDirectory = resultRoot .. "/results"
local localPlayer = Players.LocalPlayer
local userId = localPlayer and localPlayer.UserId or 0
local rawClientKey = tostring(game.PlaceId) .. "_" .. tostring(userId) .. "_" .. tostring(game.JobId)
local clientKey = string.gsub(rawClientKey, "[^%w_%-]", "_")
local resultPath = resultDirectory .. "/WZDB_" .. jobId .. "_" .. clientKey .. ".json"
local startedAt = os.time()
local logs = {}
local originalPrint = print
local originalWarn = warn
local baseEnvironment = type(getgenv) == "function" and getgenv() or _G
local printWasReplaced = false
local warnWasReplaced = false
local originalWZDB = baseEnvironment.WZDB
local wzdbWasReplaced = false
local currentStatus = "running"
local finalReturns = nil
local finalError = nil
local finalTraceback = nil

local function safeString(value)
	local valueType = typeof(value)

	if valueType == "Instance" then
		local ok, fullName = pcall(value.GetFullName, value)
		return ok and (value.ClassName .. " " .. fullName) or tostring(value)
	elseif valueType == "table" then
		local ok, encoded = pcall(HttpService.JSONEncode, HttpService, value)
		return ok and encoded or tostring(value)
	end

	local ok, text = pcall(tostring, value)
	return ok and text or "<tostring failed>"
end

local function packValues(...)
	local packed = table.pack(...)
	local values = {}

	for index = 1, packed.n do
		values[index] = safeString(packed[index])
	end

	return values
end

local function writeSnapshot(status, returns, failure, traceback)
	local payload = {
		protocol = 1,
		jobId = jobId,
		status = status,
		startedAt = startedAt,
		finishedAt = status == "running" and nil or os.time(),
		placeId = game.PlaceId,
		gameId = game.GameId,
		serverJobId = game.JobId,
		player = localPlayer and localPlayer.Name or nil,
		userId = userId,
		logs = logs,
		returns = returns,
		error = failure,
		traceback = traceback,
	}

	local encoded = HttpService:JSONEncode(payload)

	if type(makefolder) == "function" then
		pcall(makefolder, resultRoot)
		pcall(makefolder, resultDirectory)
	end

	if type(writefile) == "function" then
		local ok, writeError = pcall(writefile, resultPath, encoded)

		if not ok then
			originalWarn("[WZDB:" .. jobId .. "] writefile failed:", writeError)
		end
	else
		originalWarn("[WZDB:" .. jobId .. "] writefile is unavailable")
	end
end

local function capture(level, ...)
	table.insert(logs, {
		at = os.clock(),
		level = level,
		values = packValues(...),
	})

	if #logs > 1000 then
		table.remove(logs, 1)
	end

	writeSnapshot(currentStatus, finalReturns, finalError, finalTraceback)

	if level == "warn" then
		originalWarn("[WZDB:" .. jobId .. "]", ...)
	else
		originalPrint("[WZDB:" .. jobId .. "]", ...)
	end
end

local function capturedPrint(...)
	capture("print", ...)
end

local function capturedWarn(...)
	capture("warn", ...)
end

local WZDB = {}

function WZDB.log(label, value)
	capture("print", label, value)
	return value
end

function WZDB.runtime()
	local root = baseEnvironment.WorldZeroRuntime or baseEnvironment.WorldZeroContext
	return root and root.ActiveRuntime or root
end

function WZDB.resolve(instancePath)
	local current = game
	local first = true

	for segment in string.gmatch(tostring(instancePath), "[^%.]+") do
		if first then
			first = false
			local ok, service = pcall(game.GetService, game, segment)
			current = ok and service or game:FindFirstChild(segment)
		else
			current = current and current:FindFirstChild(segment)
		end

		if not current then
			return nil, "path_not_found:" .. tostring(instancePath)
		end
	end

	return current
end

function WZDB.require(instancePath)
	local instance, resolveError = WZDB.resolve(instancePath)

	if not instance then
		return nil, resolveError
	elseif not instance:IsA("ModuleScript") then
		return nil, "path_is_not_module:" .. tostring(instancePath)
	end

	local ok, result = pcall(require, instance)
	return ok and result or nil, ok and nil or safeString(result)
end

function WZDB.await(predicate, timeoutSeconds, intervalSeconds)
	assert(type(predicate) == "function", "WZDB.await predicate must be a function")
	local deadline = os.clock() + math.max(0, tonumber(timeoutSeconds) or 10)
	local interval = math.max(0.03, tonumber(intervalSeconds) or 0.1)

	repeat
		local result = table.pack(pcall(predicate))

		if result[1] and result[2] then
			return true, table.unpack(result, 2, result.n)
		elseif not result[1] then
			return false, safeString(result[2])
		end

		task.wait(interval)
	until os.clock() >= deadline

	return false, "timeout"
end

function WZDB.snapshot()
	writeSnapshot(currentStatus, finalReturns, finalError, finalTraceback)
	return resultPath
end

local function restoreGlobals()
	if printWasReplaced then
		pcall(function()
			baseEnvironment.print = originalPrint
		end)
	end

	if warnWasReplaced then
		pcall(function()
			baseEnvironment.warn = originalWarn
		end)
	end

	if wzdbWasReplaced then
		pcall(function()
			baseEnvironment.WZDB = originalWZDB
		end)
	end
end

writeSnapshot("running")

local chunk, compileError = loadstring(source, "=WorldZeroDevBridge/" .. jobId)

if not chunk then
	currentStatus = "compile_error"
	finalError = safeString(compileError)
	writeSnapshot(currentStatus, nil, finalError)
	originalWarn("[WZDB:" .. jobId .. "] compile error:", compileError)
	return
end

if type(setfenv) == "function" then
	local executionEnvironment = setmetatable({
		print = capturedPrint,
		warn = capturedWarn,
		WZDB = WZDB,
	}, {
		__index = baseEnvironment,
		__newindex = baseEnvironment,
	})
	pcall(setfenv, chunk, executionEnvironment)
end

printWasReplaced = pcall(function()
	baseEnvironment.print = capturedPrint
end)
warnWasReplaced = pcall(function()
	baseEnvironment.warn = capturedWarn
end)
wzdbWasReplaced = pcall(function()
	baseEnvironment.WZDB = WZDB
end)

local function errorHandler(runError)
	local traceback = nil

	if type(debug) == "table" and type(debug.traceback) == "function" then
		local ok, trace = pcall(debug.traceback, safeString(runError), 2)
		traceback = ok and trace or nil
	end

	return {
		message = safeString(runError),
		traceback = traceback,
	}
end

local packed = table.pack(xpcall(chunk, errorHandler))
restoreGlobals()

if packed[1] then
	local returned = {}

	for index = 2, packed.n do
		returned[index - 1] = safeString(packed[index])
	end

	currentStatus = "completed"
	finalReturns = returned
	writeSnapshot(currentStatus, finalReturns)
	originalPrint("[WZDB:" .. jobId .. "] completed")
else
	local failure = type(packed[2]) == "table" and packed[2] or {
		message = safeString(packed[2]),
	}
	currentStatus = "runtime_error"
	finalError = failure.message
	finalTraceback = failure.traceback
	writeSnapshot(currentStatus, nil, finalError, finalTraceback)
	originalWarn("[WZDB:" .. jobId .. "] runtime error:", failure.message)
end
`;
}

function chooseTargets(instanceId) {
	const directories = activeInstanceDirectories();

	if (instanceId) {
		const selected = directories.find((directory) => path.basename(directory) === String(instanceId));

		if (!selected) {
			throw new Error(`Real instance ${instanceId} is not active`);
		}

		return [selected];
	}

	return directories.length > 0 ? directories : [IPC_DIR];
}

function queueExecution(source, options) {
	const id = makeJobId();
	const targets = chooseTargets(options.instanceId);
	const job = {
		id,
		createdAt: new Date().toISOString(),
		sourceName: options.sourceName || "inline",
		targets: targets.map((target) => path.basename(target) || "root"),
	};
	const wrapped = buildWrappedSource(source, job);
	const jobDirectory = path.join(LOCAL_RESULT_DIR, id);

	ensureDirectory(jobDirectory);
	writeText(path.join(jobDirectory, "source.lua"), source);
	writeText(path.join(jobDirectory, "wrapped.lua"), wrapped);
	writeJson(path.join(jobDirectory, "request.json"), job);

	for (const target of targets) {
		writeText(path.join(target, "execute.txt"), wrapped);
	}

	return {
		...job,
		jobDirectory,
		expectedResults: targets.length,
	};
}

function findRemoteResults(jobId) {
	if (!fs.existsSync(REMOTE_RESULT_DIR)) {
		return [];
	}

	return fs
		.readdirSync(REMOTE_RESULT_DIR)
		.filter((name) => name.startsWith(`WZDB_${jobId}_`) && name.endsWith(".json"))
		.map((name) => path.join(REMOTE_RESULT_DIR, name));
}

function readResultFile(filePath) {
	try {
		return JSON.parse(readText(filePath));
	} catch (error) {
		return {
			status: "invalid_result",
			error: error.message,
			path: filePath,
		};
	}
}

function archiveResults(job, resultFiles) {
	const archived = [];

	for (const resultFile of resultFiles) {
		const destination = path.join(job.jobDirectory, path.basename(resultFile));
		fs.copyFileSync(resultFile, destination);
		archived.push({
			path: destination,
			result: readResultFile(destination),
		});
	}

	writeJson(
		path.join(job.jobDirectory, "summary.json"),
		archived.map((entry) => entry.result),
	);
	return archived;
}

function isTerminal(result) {
	return ["completed", "compile_error", "runtime_error", "invalid_result"].includes(result.status);
}

async function waitForResults(job, timeoutMs) {
	const started = Date.now();
	let latestFiles = [];

	while (Date.now() - started <= timeoutMs) {
		latestFiles = findRemoteResults(job.id);
		const results = latestFiles.map(readResultFile);
		const terminalCount = results.filter(isTerminal).length;

		if (terminalCount >= job.expectedResults) {
			return archiveResults(job, latestFiles);
		}

		await new Promise((resolve) => setTimeout(resolve, 150));
	}

	const archived = archiveResults(job, latestFiles);
	const running = archived.map((entry) => entry.result).filter((result) => !isTerminal(result));
	const detail = running.length > 0 ? `; ${running.length} client(s) still running` : "";
	throw new Error(`Timed out after ${timeoutMs} ms${detail}. Job: ${job.id}`);
}

function formatResult(result) {
	const lines = [
		`status: ${result.status}`,
		`client: ${result.player || "unknown"} @ place ${result.placeId || "unknown"}`,
	];

	for (const log of result.logs || []) {
		lines.push(`[${log.level}] ${(log.values || []).join("\t")}`);
	}

	if (result.returns && result.returns.length > 0) {
		lines.push(`returns: ${result.returns.join(" | ")}`);
	}

	if (result.error) {
		lines.push(`error: ${result.error}`);
	}

	if (result.traceback) {
		lines.push(result.traceback);
	}

	return lines.join("\n");
}

function findRealLauncher() {
	const updater = path.join(REAL_DIR, "Update.exe");

	if (fs.existsSync(updater)) {
		return {
			executable: updater,
			arguments: ["--processStart", "Real.exe"],
		};
	}

	const candidates = fs.existsSync(REAL_DIR)
		? fs
				.readdirSync(REAL_DIR, { withFileTypes: true })
				.filter((entry) => entry.isDirectory() && /^real-/i.test(entry.name))
				.map((entry) => path.join(REAL_DIR, entry.name, "Real.exe"))
				.filter((candidate) => fs.existsSync(candidate))
		: [];

	candidates.sort((left, right) => fs.statSync(right).mtimeMs - fs.statSync(left).mtimeMs);

	return candidates[0]
		? {
				executable: candidates[0],
				arguments: [],
			}
		: null;
}

function printHelp() {
	console.log(`World Zero DevBridge

Usage:
  WorldZeroBridge status
  WorldZeroBridge attach
  WorldZeroBridge launch
  WorldZeroBridge exec <file.lua> [--instance ID] [--timeout SECONDS] [--no-wait]
  WorldZeroBridge eval "<luau code>" [--instance ID] [--timeout SECONDS] [--no-wait]
  WorldZeroBridge probe <name> [--instance ID] [--timeout SECONDS] [--no-wait]
  WorldZeroBridge results [job-id]
  WorldZeroBridge probes
  WorldZeroBridge selftest

Environment overrides:
  WZ_REAL_DIR
  WZ_REAL_IPC
  WZ_REAL_WORKSPACE

Results are archived under:
  ${path.relative(PROJECT_DIR, LOCAL_RESULT_DIR)}
`);
}

function listLocalResults(jobId) {
	if (!fs.existsSync(LOCAL_RESULT_DIR)) {
		return [];
	}

	const directories = fs
		.readdirSync(LOCAL_RESULT_DIR, { withFileTypes: true })
		.filter((entry) => entry.isDirectory() && (!jobId || entry.name === jobId))
		.map((entry) => path.join(LOCAL_RESULT_DIR, entry.name));
	const results = [];

	for (const directory of directories) {
		for (const name of fs.readdirSync(directory)) {
			if (name.startsWith("WZDB_") && name.endsWith(".json")) {
				results.push({
					path: path.join(directory, name),
					result: readResultFile(path.join(directory, name)),
				});
			}
		}
	}

	return results;
}

async function runExecution(source, options) {
	const job = queueExecution(source, options);
	console.log(`queued job ${job.id} for ${job.targets.join(", ")}`);
	console.log(`local job directory: ${job.jobDirectory}`);

	if (options.noWait) {
		return;
	}

	const archived = await waitForResults(job, options.timeoutMs);

	for (const entry of archived) {
		console.log(`\n--- ${path.basename(entry.path)} ---`);
		console.log(formatResult(entry.result));
	}
}

async function main() {
	const argumentsList = process.argv.slice(2);
	const command = (argumentsList.shift() || "help").toLowerCase();

	if (command === "help" || command === "--help" || command === "-h") {
		printHelp();
		return;
	}

	if (command === "status") {
		const instances = activeInstanceDirectories().map((directory) => path.basename(directory));
		console.log(`Real directory: ${REAL_DIR}`);
		console.log(`IPC directory: ${IPC_DIR}`);
		console.log(`Workspace: ${REAL_WORKSPACE}`);
		console.log(`Active attached instances: ${instances.length ? instances.join(", ") : "none"}`);
		console.log(`Root execute fallback: ${path.join(IPC_DIR, "execute.txt")}`);
		return;
	}

	if (command === "attach") {
		writeText(path.join(IPC_DIR, "attach.txt"), "1");
		console.log("Attach request written.");
		return;
	}

	if (command === "launch") {
		const launcher = findRealLauncher();

		if (!launcher) {
			throw new Error("Could not find Project Real");
		}

		childProcess
			.spawn(launcher.executable, launcher.arguments, {
				detached: true,
				stdio: "ignore",
				windowsHide: true,
			})
			.unref();
		console.log("Project Real launch requested.");
		return;
	}

	if (command === "probes") {
		const probes = fs.existsSync(PROBE_DIR)
			? fs
					.readdirSync(PROBE_DIR)
					.filter((name) => name.endsWith(".lua"))
					.map((name) => path.basename(name, ".lua"))
			: [];
		console.log(probes.length > 0 ? probes.join("\n") : "No probes installed.");
		return;
	}

	if (command === "results") {
		const entries = listLocalResults(argumentsList[0]);

		for (const entry of entries) {
			console.log(`\n--- ${entry.path} ---`);
			console.log(formatResult(entry.result));
		}

		if (entries.length === 0) {
			console.log("No archived results found.");
		}
		return;
	}

	if (command === "selftest") {
		const sample = 'print("hello", game.PlaceId)\nreturn "ok", 42';
		const wrapped = buildWrappedSource(sample, { id: "selftest" });
		const selftestDirectory = path.join(LOCAL_RESULT_DIR, "selftest");

		if (!wrapped.includes(sample) || !wrapped.includes('jobId = "selftest"')) {
			throw new Error("Wrapper generation self-test failed");
		}

		writeText(path.join(selftestDirectory, "source.lua"), sample);
		writeText(path.join(selftestDirectory, "wrapped.lua"), wrapped);
		console.log("Wrapper generation: ok");
		console.log(`Generated wrapper: ${path.join(selftestDirectory, "wrapped.lua")}`);
		return;
	}

	if (!["exec", "run", "eval", "probe"].includes(command)) {
		throw new Error(`Unknown command: ${command}`);
	}

	const timeoutSeconds = Number(getOption(argumentsList, "--timeout", "30"));
	const instanceId = getOption(argumentsList, "--instance", null);
	const noWait = takeFlag(argumentsList, "--no-wait");
	const timeoutMs = Math.max(1, Number.isFinite(timeoutSeconds) ? timeoutSeconds : 30) * 1000;
	let source;
	let sourceName;

	if (command === "eval") {
		source = argumentsList.join(" ");
		sourceName = "inline";
	} else {
		let requested = argumentsList[0];

		if (!requested) {
			throw new Error(`${command} requires a file or probe name`);
		}

		if (command === "probe") {
			requested = requested.endsWith(".lua") ? requested : `${requested}.lua`;
			requested = path.join(PROBE_DIR, requested);
		} else {
			requested = path.resolve(process.cwd(), requested);
		}

		source = readText(requested);
		sourceName = path.relative(PROJECT_DIR, requested);
	}

	if (!source.trim()) {
		throw new Error("Source is empty");
	}

	await runExecution(source, {
		instanceId,
		noWait,
		timeoutMs,
		sourceName,
	});
}

main().catch((error) => {
	console.error(`World Zero DevBridge error: ${error.message}`);
	process.exitCode = 1;
});
