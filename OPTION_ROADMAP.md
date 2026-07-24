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
- Guardian Aggro Defense maintenance and four-pulse Sword Prison crowd control
- Hunter auto-summon/Frenzy, close-range Venom Trap, and emergency Divine Arrow
- Icefire Mage Super Frost priority with field-aware range guards and Meteor Crash
- Leviathan preflighted bubble chain, recursive serpent bursts, and Sea Bubble healing
- Mage group-gated Arcane Wave and range-guarded Arcane Ascension
- Mage of Light projected-health Infuse guard with automated healing, Barrier, and Grace
- Mage of Shadows nine-orb merging, autonomous hunters, Shadow Chains, and form burst modes
- Necromancer maximum-charge Spirit Burst, Hexed Cavern, and ten-summon Undead Army
- Paladin emergency support, maintained enhanced Primary, and 15-pulse Ring of Justice
- Starbreaker charge-aware Supernova, double Flare, Starforge, and Fusion sequencing
- Stormcaller health-safe Supercharge, eight-target lightning, Surge, and Thunder God
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
- Configurable Mage of Shadows skill saving and empowered-Primary Shadow Form modes
- Soul-aware Necromancer rotation with maximum-charge Burst and automatic Undead Army
- Party-health-aware Paladin healing with aggressive or emergency-only Ring modes
- Starbreaker full-meter preservation through Fusion for back-to-back Starforge uptime
- Stormcaller Thunder God sword priority with 25% long-range discharge opportunities

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
