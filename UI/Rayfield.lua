return function(ctx)
	local RayfieldUI = {}
	RayfieldUI.__index = RayfieldUI

	function RayfieldUI.new(config)
		local source = game:HttpGet(config.RayfieldUrl)
		local chunk, compileError = loadstring(source)

		if not chunk then
			error("Rayfield compile failed: " .. tostring(compileError))
		end

		local Rayfield = chunk()
		local windowConfig = config.Window
		local Window = Rayfield:CreateWindow({
			Name = windowConfig.Name,
			Icon = windowConfig.Icon,
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
		}, RayfieldUI)
	end

	function RayfieldUI:CreateTab(key, title, icon)
		if self.Tabs[key] then
			return self.Tabs[key]
		end

		local tab = self.Window:CreateTab(title, icon or 0)
		self.Tabs[key] = tab
		return tab
	end

	function RayfieldUI:CreateSection(tab, title)
		return tab:CreateSection(title)
	end

	function RayfieldUI:CreateParagraph(tab, title, content)
		return tab:CreateParagraph({
			Title = title,
			Content = content,
		})
	end

	function RayfieldUI:CreateButton(tab, options)
		return tab:CreateButton({
			Name = options.Name,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateToggle(tab, id, options)
		return tab:CreateToggle({
			Name = options.Name,
			CurrentValue = options.CurrentValue == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:CreateSlider(tab, id, options)
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
		return tab:CreateKeybind({
			Name = options.Name,
			CurrentKeybind = options.CurrentKeybind,
			HoldToInteract = options.HoldToInteract == true,
			Flag = self.Config.FlagPrefix .. id,
			Callback = options.Callback,
		})
	end

	function RayfieldUI:Notify(title, content, duration, icon)
		self.Library:Notify({
			Title = title,
			Content = content,
			Duration = duration or 5,
			Image = icon or 0,
		})
	end

	function RayfieldUI:LoadConfiguration()
		self.Library:LoadConfiguration()
	end

	function RayfieldUI:Destroy()
		self.Library:Destroy()
	end

	return RayfieldUI
end

