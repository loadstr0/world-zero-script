# Source Requests

## Received

- `ReplicatedStorage.Client.Actions`
- `ReplicatedStorage.Shared.Skills`

The supplied sources confirm that `UseSkill(slot)` resolves metadata through `Shared.Skills`, then dispatches to the current class module under `Shared.Combat.Skillsets`.

## Next priority

Please extract the full source for these modules next, in this order:

1. `ReplicatedStorage.Shared.Combat.Skillsets.Swordmaster`
2. `ReplicatedStorage.Shared.Combat`
3. `ReplicatedStorage.Shared.Mobs`
4. `ReplicatedStorage.Shared.Gamebeast.Infra.Shared.Modules.GetRemote`
5. `ReplicatedStorage.Shared.Drops`
6. `ReplicatedStorage.Shared.Missions`
7. `ReplicatedStorage.Shared.Missions.MissionData`
8. `ReplicatedStorage.Shared.Teleport`
9. `ReplicatedStorage.Shared.Teleport.WorldData`

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
