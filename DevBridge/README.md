# World Zero DevBridge

Local command-line bridge for sending diagnostic Luau jobs to an attached Project Real client.

It uses Project Real's existing filesystem IPC. It does not open a port, run an HTTP server, or accept network requests.

## Start

From the repository:

```powershell
.\DevBridge\WorldZeroBridge.cmd status
.\DevBridge\WorldZeroBridge.cmd attach
.\DevBridge\WorldZeroBridge.cmd probes
.\DevBridge\WorldZeroBridge.cmd probe runtime-status
```

Run a file:

```powershell
.\DevBridge\WorldZeroBridge.cmd exec .\DevBridge\probes\quest-dungeon.lua
```

Run a short expression:

```powershell
.\DevBridge\WorldZeroBridge.cmd eval "print(game.PlaceId); return game.PlaceId"
```

Built-in probes:

- `runtime-status` checks initialization, enabled supervisors, navigation, dungeon phase, and teleport restoration.
- `quest-dungeon` lists real story candidates and verifies quest-to-mission routing.
- `dungeon-runtime` scans mission state, protected objects, start triggers, workspace mechanics, and objective UI.
- `gear-runtime` compares maximum-potential gear against equipped items and explains upgrade/equip gates.
- `option-health` audits every major integration and automation engine in one result.

Useful options:

- `--instance ID` targets one attached Real instance.
- `--timeout SECONDS` changes how long the CLI waits for terminal results.
- `--no-wait` queues the job without waiting.

Each execution creates `DevBridge/results/<job-id>/` containing:

- `request.json`
- original `source.lua`
- generated `wrapped.lua`
- one JSON result per Roblox client
- `summary.json`

The Luau wrapper captures:

- `print` and `warn`
- returned values
- compilation failures
- runtime errors and tracebacks
- place, server, player, and user identifiers
- live `running` snapshots

Captured output is still forwarded to the executor console with a `[WZDB:<job-id>]` prefix.

## Injected helpers

Every wrapped job receives a temporary `WZDB` table:

- `WZDB.log(label, value)` records and returns a value.
- `WZDB.runtime()` returns the active World Zero runtime.
- `WZDB.resolve("ReplicatedStorage.Shared.Teleport")` resolves an instance path.
- `WZDB.require("ReplicatedStorage.Shared.Teleport")` safely requires a module path.
- `WZDB.await(predicate, timeout, interval)` waits for a replicated condition.
- `WZDB.snapshot()` immediately flushes the current result JSON.

The previous global `WZDB`, `print`, and `warn` values are restored after the main job finishes.

## Safety

This intentionally executes arbitrary Luau in the attached client. The bridge is local-only, but files passed to `exec` or `eval` should still be reviewed. A CLI timeout only stops waiting for a response; it cannot forcibly terminate Luau that is already running in Roblox.
