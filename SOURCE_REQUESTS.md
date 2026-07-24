# Source Requests

## Received

- `ReplicatedStorage.Client.Actions`
- `ReplicatedStorage.Shared.Skills`
- `ReplicatedStorage.Shared.Combat.Skillsets.Swordmaster`
- `ReplicatedStorage.Shared.Combat.Skillsets.Archer`
- `ReplicatedStorage.Shared.Combat.Skillsets.Assassin`
- `ReplicatedStorage.Shared.Combat.Skillsets.Berserker`
- `ReplicatedStorage.Shared.Combat.Skillsets.Defender`
- `ReplicatedStorage.Shared.Combat.Skillsets.Demon`
- `ReplicatedStorage.Shared.Combat.Skillsets.Dragoon`
- `ReplicatedStorage.Shared.Combat.Skillsets.DualWielder`
- `ReplicatedStorage.Shared.Combat.Skillsets.Greatsword`
- `ReplicatedStorage.Shared.Combat.Skillsets.Guardian`
- `ReplicatedStorage.Shared.Combat.Skillsets.Hunter`
- `ReplicatedStorage.Shared.Combat.Skillsets.IcefireMage`
- `ReplicatedStorage.Shared.Combat.Skillsets.Leviathan`
- `ReplicatedStorage.Shared.Combat.Skillsets.Mage`
- `ReplicatedStorage.Shared.Combat.Skillsets.MageOfLight`
- `ReplicatedStorage.Shared.Combat.Skillsets.MageOfShadows`
- `ReplicatedStorage.Shared.Combat.Skillsets.Necromancer`
- `ReplicatedStorage.Shared.Combat.Skillsets.Paladin`
- `ReplicatedStorage.Shared.Combat.Skillsets.Starbreaker`
- `ReplicatedStorage.Shared.Combat.Skillsets.Stormcaller`
- `ReplicatedStorage.Shared.Combat.Skillsets.Summoner`
- `ReplicatedStorage.Shared.Combat.Skillsets.Warlord`
- `ReplicatedStorage.Shared.Combat.Skillsets.General`
- `ReplicatedStorage.Shared.Combat`
- `ReplicatedStorage.Shared.Profile`
- `ReplicatedStorage.Shared.Mobs`
- `ReplicatedStorage.Shared.Health`
- `ReplicatedStorage.Shared.Status`
- `ReplicatedStorage.Shared.Status.Statuses`
- `ReplicatedStorage.Shared.WalkspeedManager`

The supplied sources confirm that `UseSkill(slot)` resolves metadata through `Shared.Skills`, then dispatches to the current class module under `Shared.Combat.Skillsets`. Swordmaster, Archer, Assassin, Berserker, Defender, Demon, Dragoon, Dual Wielder, Guardian, Hunter, Icefire Mage, Leviathan, Mage, Mage of Light, Mage of Shadows, Necromancer, Paladin, Starbreaker, Stormcaller, Summoner, and Warlord have verified automation panels. Greatsword has a verified source-status panel, but its supplied module is an unfinished non-damaging prototype. `General` only supplies the shared Sprint slot. `Shared.Combat` reconstructs skill hitboxes and rate-limits skill identifiers on the server. `Shared.Profile` mirrors `Profile.Class.Value` to the player's `Class` attribute whenever the equipped class changes.

## Next priority

All supplied production class skillsets now have class-aware UI coverage. Greatsword remains intentionally limited to source status because its supplied implementation is a non-damaging prototype.

Mob filtering, boss/elite/name targeting, ownership checks, exact summon tracking, barrier-aware survival, catalog-driven status responses, and speed-aware kiting are now implemented.

Run `Tools/SourceExporter.lua` in the game to collect the remaining batch in one operation. It requests these priority sources recursively where appropriate:

1. `ReplicatedStorage.Shared.Status.Statuses.Frozen`
2. `ReplicatedStorage.Shared.Status.Statuses.FrozenFreezeTag`
3. `ReplicatedStorage.Shared.Settings`
4. `ReplicatedStorage.Shared.Gear`
5. `ReplicatedStorage.Shared.Gamebeast.Infra.Shared.Modules.GetRemote`
6. `ReplicatedStorage.Shared.Drops`
7. `ReplicatedStorage.Shared.Missions`
8. `ReplicatedStorage.Shared.Missions.MissionData`
9. `ReplicatedStorage.Shared.Teleport`
10. `ReplicatedStorage.Shared.Teleport.WorldData`

The two Frozen handlers may reveal whether normal Frozen/Heartbreak has a client break-free action that can be automated; Freeze Tag explicitly requires another player. `Shared.Settings` and `Shared.Gear` remain the next speed/perk sources after that.

After those, the next useful client modules are:

- `ReplicatedStorage.Client.Gui.GuiScripts.MissionObjective`
- `ReplicatedStorage.Client.Gui.GuiScripts.MissionQueue`
- `ReplicatedStorage.Client.Gui.GuiScripts.MissionSelect`
- `ReplicatedStorage.Client.Gui.GuiScripts.QuestTracker`
- `ReplicatedStorage.Client.Gui.GuiScripts.HubTeleport`
- `ReplicatedStorage.Client.Gui.GuiScripts.WorldTeleport`
- `ReplicatedStorage.Client.Gui.GuiScripts.LootReceived`

If your extractor also supports instance-tree scans, capture the names and classes of:

- Direct children of `ReplicatedStorage` that are RemoteEvents or RemoteFunctions
- The live workspace folders containing mobs/enemies
- The live workspace folders containing drops, chests, and mission objectives

Do not invoke the admin command modules. They are useful as naming clues only and may be server-authorized.
