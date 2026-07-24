# Option Roadmap

## Available now

- Class-aware skill selector
- Manual primary and selected-skill activation
- Nearest-target aim
- Experimental nearest-target Auto Primary
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate controls
- Sprint, mount, sheath, and quick-item controls
- Persistent Rayfield configuration
- GitHub update checks and optional live auto-reload

## High-power combat options

### Kill Aura

Planned controls:

- Enable toggle
- Aura range
- Target mode: nearest or all
- Attack mode: primary, selected skill, or rotation
- Attack interval
- Boss-only and mob-name filters

Required source:

1. `ReplicatedStorage.Shared.Combat`
2. `ReplicatedStorage.Shared.Mobs`

Swordmaster's normal attack behavior is now verified. The existing rotation is still not considered a finished kill aura because target validation and mob enumeration remain unverified.

### Skill Aura / Rotation

Available now:

- Automatic Skill1/Skill2 rotation
- Cooldown-aware priority

Still requires more source:

- Automatic Ultimate usage with a verified full-energy check
- Minimum target count per skill
- Boss burst mode

### Other possible high-power options

- Auto farm with target and world filters
- Auto mission selection/repeat
- Auto loot and chest collection
- Boss targeting and phase-aware attacks
- Mob vacuum only if the game exposes client-authoritative movement
- Cooldown modification only if server validation permits it

Options that are enforced by the server will be marked unavailable instead of presented as working.
