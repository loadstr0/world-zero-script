# World Zero Script

Modular Rayfield project modeled after the Eldorado Lua bridge and loader architecture.

## Entry points

- `Bootstrap.lua` is the single-file public execution entry point.
- `ExampleBridge.lua` supplies runtime settings and starts `Loader.lua`.
- `Loader.lua` fetches modules in dependency order, initializes each with a shared context, and calls `Main.Start(ctx)`.
- `world_zero_bridge.example.json` is the file-based alternative for executors with workspace file access.

## Module contract

Every implementation module returns a factory:

```lua
return function(ctx)
	local Module = {}
	return Module
end
```

Dependencies are obtained with `ctx:Require("ModuleName")`. Shared Roblox services are exposed through `ctx.Services`.

## Layout

```text
World Zero Script/
|-- Loader.lua
|-- ExampleBridge.lua
|-- Core/
|   |-- Config.lua
|   |-- Executor.lua
|   |-- Janitor.lua
|   |-- Logger.lua
|   `-- State.lua
|-- Game/
|   |-- Actions.lua
|   |-- Skills.lua
|   `-- Context.lua
|-- UI/
|   |-- Navigation.lua
|   `-- Rayfield.lua
|-- Features/
|   |-- Combat.lua
|   |-- Farming.lua
|   |-- Home.lua
|   |-- Loot.lua
|   |-- Missions.lua
|   |-- Player.lua
|   |-- Settings.lua
|   `-- Teleports.lua
`-- Main.lua
```

Feature modules currently register their Rayfield tabs but deliberately contain no guessed game calls. They will be filled in as requested World Zero source is supplied.

`Game/Actions.lua` is the guarded adapter for the live `ReplicatedStorage.Client.Actions` module. Feature modules should use this adapter instead of requiring the game module directly.

Executor-specific globals are centralized in `Core/Executor.lua`. Other modules should use its normalized capability fields rather than directly assuming `syn.*` or one executor's aliases exist.

`Core/Updater.lua` checks the public GitHub `main` commit and can reload the modular runtime when a new commit is detected.

## Current controls

The verified `Client.Actions` source supports these initial Rayfield controls:

- Target-range and aim-duration sliders
- One-shot nearest-target aim
- Optional aim before primary attacks
- Manual and automatic primary attacks
- Configurable attack-check interval
- Sprint toggle
- Mount and sheath buttons
- Quick-item name input and use button

Skill names and slots are now available from `Shared.Skills`; class-specific execution details still require the relevant class skillset source.

The Combat tab now reads the live `Shared.Skills` catalog, identifies the current class through `Shared.Profile`, and builds a class-specific skill dropdown. Skill execution remains routed through `Client.Actions`.

## Rayfield navigation

The visible interface is intentionally smaller than the module tree:

- Home
- Automation — Farming, Missions, and Loot sections
- Combat
- Travel
- Player
- Settings

`UI/Navigation.lua` owns tab names, icons, and keys. Feature implementation remains split across separate modules even when multiple features share one visible tab.

## Publish and execute

This folder is configured for the public repository `loadstr0/world-zero-script`.

Execute it with:

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/loadstr0/world-zero-script/main/Bootstrap.lua"))()
```

The repository must be public for this unauthenticated raw URL. Local research files and decompiled references are excluded by `.gitignore`.

## Configuration and updates

Rayfield automatically saves all flagged controls. The Settings tab reports the active configuration folder/file and can reload saved values.

Every fresh execution downloads the latest GitHub modules. The Settings tab also supports manual update checks, configurable polling, and optional automatic runtime reload when `main` changes.
