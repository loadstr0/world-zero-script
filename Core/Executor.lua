return function()
	local Executor = {}

	local function firstFunction(...)
		for index = 1, select("#", ...) do
			local candidate = select(index, ...)

			if typeof(candidate) == "function" then
				return candidate
			end
		end

		return nil
	end

	local synLibrary = type(syn) == "table" and syn or {}
	local httpLibrary = type(http) == "table" and http or {}

	Executor.Request = firstFunction(
		request,
		http_request,
		synLibrary.request,
		httpLibrary.request
	)

	Executor.ReadFile = firstFunction(readfile)
	Executor.WriteFile = firstFunction(writefile)
	Executor.AppendFile = firstFunction(appendfile)
	Executor.IsFile = firstFunction(isfile)
	Executor.ListFiles = firstFunction(listfiles)
	Executor.MakeFolder = firstFunction(makefolder)

	Executor.QueueOnTeleport = firstFunction(
		queue_on_teleport,
		synLibrary.queue_on_teleport
	)

	Executor.GetScripts = firstFunction(getscripts)
	Executor.GetLoadedModules = firstFunction(getloadedmodules)
	Executor.GetScriptEnvironment = firstFunction(getsenv)
	Executor.GetGarbageCollection = firstFunction(getgc)

	function Executor.Has(name)
		return type(Executor[name]) == "function"
	end

	function Executor.Report()
		return {
			Request = Executor.Has("Request"),
			ReadFile = Executor.Has("ReadFile"),
			WriteFile = Executor.Has("WriteFile"),
			ListFiles = Executor.Has("ListFiles"),
			QueueOnTeleport = Executor.Has("QueueOnTeleport"),
			GetScripts = Executor.Has("GetScripts"),
			GetLoadedModules = Executor.Has("GetLoadedModules"),
			GetScriptEnvironment = Executor.Has("GetScriptEnvironment"),
			GetGarbageCollection = Executor.Has("GetGarbageCollection"),
		}
	end

	return Executor
end

