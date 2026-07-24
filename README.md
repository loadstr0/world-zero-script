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
|   |-- ClassRegistry.lua
|   |-- Combat.lua
|   |-- Context.lua
|   |-- Energy.lua
|   |-- Health.lua
|   |-- Profile.lua
|   |-- Status.lua
|   |-- Skills.lua
|   `-- Classes/
|       |-- Assassin.lua
|       |-- Archer.lua
|       |-- Berserker.lua
|       |-- Defender.lua
|       |-- Demon.lua
|       |-- Dragoon.lua
|       |-- DualWielder.lua
|       |-- Greatsword.lua
|       |-- Guardian.lua
|       |-- Hunter.lua
|       |-- IcefireMage.lua
|       |-- Leviathan.lua
|       |-- Mage.lua
|       |-- MageOfLight.lua
|       |-- MageOfShadows.lua
|       |-- Necromancer.lua
|       |-- Paladin.lua
|       `-- Swordmaster.lua
|-- UI/
|   |-- Navigation.lua
|   `-- Rayfield.lua
|-- Features/
|   |-- Classes/
|   |   |-- Assassin.lua
|   |   |-- Archer.lua
|   |   |-- Berserker.lua
|   |   |-- Defender.lua
|   |   |-- Demon.lua
|   |   |-- Dragoon.lua
|   |   |-- DualWielder.lua
|   |   |-- Greatsword.lua
|   |   |-- Guardian.lua
|   |   |-- Hunter.lua
|   |   |-- IcefireMage.lua
|   |   |-- Leviathan.lua
|   |   |-- Mage.lua
|   |   |-- MageOfLight.lua
|   |   |-- MageOfShadows.lua
|   |   |-- Necromancer.lua
|   |   |-- Paladin.lua
|   |   `-- Swordmaster.lua
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

Feature modules register Rayfield controls only when the corresponding World Zero behavior has been verified from supplied source.

`Game/Actions.lua` is the guarded adapter for the live `ReplicatedStorage.Client.Actions` module. Feature modules should use this adapter instead of requiring the game module directly.

Executor-specific globals are centralized in `Core/Executor.lua`. Other modules should use its normalized capability fields rather than directly assuming `syn.*` or one executor's aliases exist.

`Core/Updater.lua` checks the public GitHub `main` commit and can reload the modular runtime when a new commit is detected.

## Current controls

The verified `Client.Actions` source supports these initial Rayfield controls:

- Target-range and aim-duration sliders
- One-shot nearest-target aim
- Optional aim before primary attacks
- Manual primary attacks for every detected class
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Server-validated target scanning and minimum-target gating
- Server-safe Swordmaster aura through normal skill execution
- Archer ranged aura with configurable skills and automatic charged Ultimate
- Assassin shadow-critical aura with gap closing and automatic full-energy Ultimate
- Berserker Rage burst aura with upgraded fire skills and full-energy activation
- Defender eight-hit rotation with conditional party-healing Shield automation
- Demon Prince burst aura with health-guarded Dark Binding and Life Steal recovery
- Dragoon live Dragon Chain completion and 18-dragon full-energy burst
- Dual Wielder maximum-speed Tempo, kill-healing, and 29-event Ultimate rotation
- Guardian Aggro Defense, enemy draw, and four-pulse Sword Prison control
- Hunter Familiar management, Venom Trap control, and healing Divine Arrow
- Icefire Mage range-guarded elemental rotation and 11-event Meteor Crash
- Leviathan recursive bubble chains, Sea Bubble healing, and invincible burst
- Mage group-aware Arcane Wave and full-energy Arcane Ascension
- Mage of Light health-safe Infused Orbs, healing, Barrier, and Grace
- Mage of Shadows autonomous orb hunters, six-pulse Chains, and Shadow Form burst
- Necromancer soul-aware Spirit Burst, six-pulse Cavern, and ten-summon Undead Army
- Paladin health-aware blocking, party Retribution, maintained Light, and healing Ring
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate buttons
- Configurable attack-check interval
- Sprint toggle
- Mount and sheath buttons
- Quick-item name input and use button

Skill names and slots are available from `Shared.Skills`. Swordmaster, Archer, Assassin, Berserker, Defender, Demon, Dragoon, Dual Wielder, Guardian, Hunter, Icefire Mage, Leviathan, Mage, Mage of Light, Mage of Shadows, Necromancer, and Paladin execution details are verified through their respective `Shared.Combat.Skillsets` modules; other classes still require their relevant skillset source.

The supplied Greatsword module is also source-verified, but it is an unfinished non-damaging prototype: its only hit callback prints `HIT`, and it defines no class skills or Ultimate. The class-aware panel reports that limitation and deliberately does not expose fake automation.

The Combat tab reads the live `Shared.Skills` catalog and identifies the equipped class through the replicated `LocalPlayer.Class` attribute verified in `Shared.Profile`. `Game/ClassRegistry.lua` selects only the matching verified class panel. A class change automatically rebuilds the interface, while skill execution remains routed through `Client.Actions`.

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
loadstring(game:HttpGet(
	"https://raw.githubusercontent.com/loadstr0/world-zero-script/main/Bootstrap.lua?cache="
		.. tostring(os.time())
))()
```

The runtime prints labeled `INITIALIZATION START` and `INITIALIZATION END` boundaries around all feature-registration output.

The repository must be public for this unauthenticated raw URL. Local research files and decompiled references are excluded by `.gitignore`.

## Configuration and updates

Rayfield automatically saves all flagged controls. The Settings tab reports the active configuration folder/file and can reload saved values.

Every fresh execution downloads the latest GitHub modules. The Settings tab also supports manual update checks, configurable polling, and optional automatic runtime reload when `main` changes.
