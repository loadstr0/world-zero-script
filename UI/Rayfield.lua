return function(ctx)
	local RayfieldUI = {}
	RayfieldUI.__index = RayfieldUI

	local Logger = ctx:Require("Logger")
	local Executor = ctx:Require("Executor")

	local function destroyStaleRayfieldWindows(config)
		if Executor.Has("SetThreadIdentity") then
			local runtimeConfig = config.Runtime or {}
			pcall(Executor.EnsureThreadIdentity, runtimeConfig.ThreadIdentity)
		end

		pcall(function()
			local coreGui = game:GetService("CoreGui")
			local robloxGui = coreGui:FindFirstChild("RobloxGui")

			for _, child in ipairs(robloxGui and robloxGui:GetChildren() or {}) do
				if
					child:IsA("ScreenGui")
					and (child.Name == "Rayfield" or child.Name == "Rayfield-Old")
				then
					child:Destroy()
				end
			end
		end)
	end

	local function prepareUIThread(self)
		if not Executor.Has("SetThreadIdentity") then
			return
		end

		local runtimeConfig = self.Config.Runtime or {}
		local ok, identityError = Executor.EnsureThreadIdentity(runtimeConfig.ThreadIdentity)

		if not ok and not self.IdentityWarningShown then
			self.IdentityWarningShown = true
			Logger.warn("Rayfield thread identity restore failed:", identityError)
		end
	end

	local function normalizeIcon(icon)
		-- Rayfield treats string icons as Lucide names. Unsupported names can
		-- throw inside Rayfield and prevent every later tab from registering.
		-- Numeric Roblox image IDs remain safe across Rayfield versions.
		if type(icon) == "number" then
			return icon
		end

		return 0
	end

	function RayfieldUI.new(config)
		destroyStaleRayfieldWindows(config)
		local source = game:HttpGet(config.RayfieldUrl)
		local chunk, compileError = loadstring(source)

		if not chunk then
			error("Rayfield compile failed: " .. tostring(compileError))
		end

		local Rayfield = chunk()
		local windowConfig = config.Window
		local Window = Rayfield:CreateWindow({
			Name = windowConfig.Name,
			Icon = normalizeIcon(windowConfig.Icon),
			LoadingTitle = windowConfig.LoadingTitle,
			LoadingSubtitle = windowConfig.LoadingSubtitle,
			ShowText = windowConfig.ShowText,
			Theme = windowConfig.Theme,
			ToggleUIKeybind = windowConfig.ToggleUIKeybind,
			DisableRayfieldPrompts = windowConfig.DisableRayfieldPrompts,
			DisableBuildWarnings = windowConfig.DisableBuildWarnings,
			ConfigurationSaving = config.ConfigurationSaving,
			Discord = {
				Enabled = false,
				Invite = "",
				RememberJoins = true,
			},
			KeySystem = false,
		})

		return setmetatable({
			Library = Rayfield,
			Window = Window,
			Config = config,
			Tabs = {},
			IdentityWarningShown = false,
		}, RayfieldUI)
	end

	function RayfieldUI:CreateTab(key, title, icon)
		if self.Tabs[key] then
			return self.Tabs[key]
		end

		prepareUIThread(self)
		local ok, tab = pcall(function()
			return self.Window:CreateTab(title, normalizeIcon(icon))
		end)

		if not ok then
			local fallback = self.Tabs.Automation or self.Tabs.Home

			if not fallback then
				error("Rayfield could not create tab " .. tostring(title) .. ": " .. tostring(tab), 2)
			end

			Logger.warn(
				"Rayfield compatibility fallback:",
				title,
				"was placed in an existing tab because:",
				tab
			)
			tab = fallback
		end

		self.Tabs[key] = tab
		return tab
	end

	function RayfieldUI:CreateNavigationTab(item)
		return self:CreateTab(item.Key, item.Title, item.Icon)
	end

	function RayfieldUI:CreateSection(tab, title)
		prepareUIThread(self)
		local ok, section = pcall(function()
			return tab:CreateSection(title)
		end)

		if ok then
			return section
		end

		Logger.warn("Rayfield skipped section heading:", title, section)
		return {
			Set = function() end,
		}
	end

	function RayfieldUI:CreateParagraph(tab, title, content)
		prepareUIThread(self)
		return tab:CreateParagraph({
			Title = title,
			Content = content,
		})
	end

	function RayfieldUI:CreateButton(tab, options)
		prepareUIThread(self)
		return tab:CreateButton({
			Name = options.Name,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateToggle(tab, id, options)
		prepareUIThread(self)
		return tab:CreateToggle({
			Name = options.Name,
			CurrentValue = options.CurrentValue == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateSlider(tab, id, options)
		prepareUIThread(self)
		return tab:CreateSlider({
			Name = options.Name,
			Range = options.Range,
			Increment = options.Increment or 1,
			Suffix = options.Suffix or "",
			CurrentValue = options.CurrentValue,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateDropdown(tab, id, options)
		prepareUIThread(self)
		return tab:CreateDropdown({
			Name = options.Name,
			Options = options.Options,
			CurrentOption = options.CurrentOption,
			MultipleOptions = options.MultipleOptions == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateInput(tab, id, options)
		prepareUIThread(self)
		return tab:CreateInput({
			Name = options.Name,
			CurrentValue = options.CurrentValue or "",
			PlaceholderText = options.PlaceholderText or "",
			RemoveTextAfterFocusLost = options.RemoveTextAfterFocusLost == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateKeybind(tab, id, options)
		prepareUIThread(self)
		return tab:CreateKeybind({
			Name = options.Name,
			CurrentKeybind = options.CurrentKeybind,
			HoldToInteract = options.HoldToInteract == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:Notify(title, content, duration, icon)
		prepareUIThread(self)
		self.Library:Notify({
			Title = title,
			Content = content,
			Duration = duration or 5,
			Image = normalizeIcon(icon),
		})
	end

	function RayfieldUI:LoadConfiguration()
		prepareUIThread(self)
		self.Library:LoadConfiguration()
	end

	function RayfieldUI:Destroy()
		prepareUIThread(self)
		self.Library:Destroy()
	end

	return RayfieldUI
end
