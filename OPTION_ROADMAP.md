# Option Roadmap

## Available now

- Class-aware skill selector
- Live equipped-class detection and automatic UI rebuilding
- Registry-driven class panels; unsupported classes show only verified generic controls
- Manual primary and selected-skill activation
- Nearest-target aim
- Experimental nearest-target Auto Primary
- Swordmaster auto-unsheath and cooldown-aware Skill1/Skill2 rotation
- Direct Crescent Strike, Leap Slash, Dodge, and charged Ultimate controls
- Server-validated radius scan and minimum-target gating
- Server-safe Swordmaster combat aura through normal skill execution
- Archer ranged aura with Skill1/Skill2/Skill3 rotation and charged Ultimate
- Assassin Shadow Cloak, Shadow Leap, Shadow Strike, and full-energy Ultimate rotation
- Berserker Rage burst mode with Aggro Slam, eight-hit Giga Spin, and Fissure
- Defender conditional party-heal automation with eight-hit Cyclone and Groundbreaker
- Demon Prince burst mode with chained Scythe Throw and health-guarded Dark Binding
- Dragoon live Dragon Chain completion with marked-target bonus and Dragon Dance
- Dual Wielder maximum-speed Tempo, 5% kill-healing, and multi-stage Ultimate
- Greatsword source-aware disabled panel for its current non-damaging prototype
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

1. `ReplicatedStorage.Shared.Mobs`

Swordmaster behavior and server hitbox validation are now verified. The direct `AttackTarget` remote is explicitly flagged as autofarming, and invalid damage identifiers are recorded as Kill Aura before a delayed kick. Those trap paths are deliberately not exposed. `Shared.Mobs` is still required for boss and mob-name filters.

### Skill Aura / Rotation

Available now:

- Automatic Skill1/Skill2 rotation
- Cooldown-aware priority
- Automatic Assassin Ultimate usage with a verified full-energy check

Still requires more source:

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
