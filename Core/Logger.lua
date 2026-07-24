return function(ctx)
	local Logger = {}

	local function enabled()
		local bridge = ctx.Bridge or {}
		return bridge.Debug ~= false
	end

	local function emit(method, ...)
		if method == "print" and not enabled() then
			return
		end

		local values = table.pack(...)
		local output = { "[WorldZero]" }

		for index = 1, values.n do
			table.insert(output, tostring(values[index]))
		end

		if method == "warn" then
			warn(table.concat(output, " "))
		else
			print(table.concat(output, " "))
		end
	end

	function Logger.info(...)
		emit("print", ...)
	end

	function Logger.warn(...)
		emit("warn", ...)
	end

	function Logger.error(...)
		emit("warn", "ERROR", ...)
	end

	return Logger
end

