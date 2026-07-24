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

	Executor.GetThreadIdentity = firstFunction(
		getthreadidentity,
		get_thread_identity,
		getidentity,
		getthreadcontext,
		synLibrary.get_thread_identity
	)

	Executor.SetThreadIdentity = firstFunction(
		setthreadidentity,
		set_thread_identity,
		setidentity,
		setthreadcontext,
		synLibrary.set_thread_identity
	)

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

	local initialThreadIdentity = nil

	if Executor.GetThreadIdentity then
		local ok, identity = pcall(Executor.GetThreadIdentity)

		if ok then
			initialThreadIdentity = tonumber(identity)
		end
	end

	function Executor.Has(name)
		return type(Executor[name]) == "function"
	end

	function Executor.GetInitialThreadIdentity()
		return initialThreadIdentity
	end

	function Executor.EnsureThreadIdentity(identity)
		if not Executor.SetThreadIdentity then
			return false, "thread_identity_control_unavailable"
		end

		local target = tonumber(identity) or initialThreadIdentity or 8
		local ok, setError = pcall(Executor.SetThreadIdentity, target)

		if not ok then
			return false, "thread_identity_set_failed:" .. tostring(setError)
		end

		-- Synapse-compatible setters apply after the next scheduler cycle.
		task.wait()
		return true
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
			ThreadIdentityControl = Executor.Has("SetThreadIdentity"),
		}
	end

	return Executor
end
