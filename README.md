# Dungeon Adventurer

```text
          ╔════════════════════════════════════════╗
          ║  DUNGEON ADVENTURER                  ║
          ║  ASCII tactics. Dangerous treasure.   ║
          ║  One more floor.                      ║
          ╚════════════════════════════════════════╝
```

**Dungeon Adventurer** is a Godot 4.4 ASCII-first roguelike dungeon crawler with optional Hybrid and Full Pixel Map presentation, D&D 5e-inspired mechanics, turn-based dungeon tactics, floor-scaling loot, dangerous biomes, readable combat logs, and the constant bad idea of going one floor deeper.

Play the current web build here:

**https://damiankovac0-pixel.github.io/DND-Roguelike-Dungeon-Crawler/**

## About it

This is a crunchy little dungeon machine dressed like an old terminal and tuned like a tabletop crawl.

You roll a character, pick a class, descend into procedurally generated floors, bump into monsters, open suspicious chests, sell loot to a shopkeeper who definitely should not be down there, and try to survive long enough to decide whether victory is enough or whether greed is louder.

The game is built around a simple promise:

> Every floor should ask a small tactical question, then offer a shiny reason to make a worse decision.

The dungeon keeps its ASCII identity across all three map modes. ASCII renders the complete map as symbols; Hybrid combines pixel terrain, actors, items, and effects with ASCII tactical markers; Full Pixel renders the complete tactical map in pixel art. Menus, HUD, combat log, and accessibility cues remain terminal-inspired in every mode.

The dungeon has five themed arcs:

| Floors | Biome | Mood | Boss / Capstone hook |
| --- | --- | --- | --- |
| 1-5 | The Tower | Marble, silver, watching stone | The Observer, Shard of Sight |
| 6-10 | The Rotting Garden | Gold-green rot, saintly thorns | Seraphine, The Thorn Saint |
| 11-15 | The Cinder Wastes | Ember, ash, hunger | Vorrak, The Ashen Maw |
| 16-20 | The Sunken Halls | Rusted bronze, black water | Kaelros, The Drowned King |
| 21-25 | The Glass Labyrinth | Mirrors, purple light, bad reflections | Nyxara, The Mirror Witch |
| 26+ | Endless Deeps | Post-victory descent | No promise of mercy |

Reach floor 25 and you can leave victorious. Or keep delving forever, because the dungeon has excellent marketing and no ethics.

## What is in the game

### Core crawl

- Procedural dungeon floors with rooms, corridors, doors, stairs, secret rooms, traps, containers, clutter, and biome color bands.
- Turn-based movement and bump combat.
- Fog-of-war / field-of-view map rendering.
- Message log with combat, loot, trap, shop, and system feedback.
- Floor scaling for enemies, item pools, gold rewards, chest rarity, shop stock, and XP.

### Character systems

- D&D-style ability scores and modifiers.
- Character classes: **Fighter**, **Ranger**, and **Wizard**.
- Class abilities through the `Q` menu, with deeper progression and unlock-level gating.
- Level-ups that improve ability scores up to the current caps.
- Character sheet, inventory, equipment, consumables, and run archive.

### Combat and enemies

- d20-style attack resolution against AC.
- Damage types and enemy affinities: some creatures resist, some are weak, some are simply rude.
- Melee enemies, ranged enemies, casters, summoners, sleepers, aware threats, and intent markers.
- Enemy telegraphs for visible threats so the dungeon feels dangerous without becoming unreadable.
- Boss data/resources for five named biome capstones.

### Loot, shops, and greed

- Weapons, armor, accessories, scrolls, potions, gold, XP orbs, chests, and shop stock.
- Rarity tiers with color treatment and high-rarity shimmer effects.
- Class-restricted gear and gear set bonuses.
- Shop buying, selling, rerolling, and floor-scaled item previews.

### Atmosphere

- Terminal-style ASCII UI.
- Animated title/library/character creation backdrops.
- Sensory feedback layer with procedural audio cues, ambience, screen flashes, reduced-VFX mode, and pause-menu controls.
- Optional Hybrid and Full Pixel Map rendering with 16×16 biome terrain, individually authored animated actors, unique item ground art, pixel effects, and deterministic nearest-neighbour scaling.
- Boss battle audio assets for the current boss encounter direction.

### Library / codex

The in-game Library is the lore-and-rules desk:

- Dungeon notes.
- Bestiary entries.
- Item and trap references.
- Class ability reference.
- Version history.
- Run archive for completed non-debug runs.

### V31 boss and Hard-mode release

- Normal bosses now pair tighter phase-, range-, and cooldown-aware scheduling with distinct close-range counters, readable one-turn tells, contextual attack audio, and boss-specific spawn effects.
- Normal and Hard can be selected during character creation. Hard unlocks only after an **archived, non-debug Normal victory**.
- Hard adds visually distinct elites from floor 3 onward, tougher regular enemies and bosses, scarcer enemy gold, higher buy and reroll costs, reduced sell returns, and adjusted elite and boss rewards.
- Each Hard boss gains channel-immunity counterplay: the Observer blocks ranged damage while its eye is closed; Seraphine, Vorrak, and Nyxara adapt to repeated damage channels and force signature retaliations; and Kaelros blocks magic while a retainer lives.

### V30 visual release

- Distinct animated pixel sprites for all 37 non-boss enemies, while the five oversized boss sheets retain their multi-cell presentation.
- Unique 16×16 ground sprites for all 76 item resources, plus rarity-coloured idle enchantment treatment for rare and higher equipment.
- Class-specific melee, bow, staff, scroll, potion, and class-ability animations.
- Dedicated cracked-wall terrain in pixel modes; ASCII mode retains its established symbol language.
- Focus-, hover-, keyboard-, and controller-driven pixel previews in the Library Bestiary, Scribes, and Dungeon Notes browsers.
- Accelerating held-key inventory navigation and boss reward chests that appear after the death animation at the defeated boss footprint.

## Controls

| Action | Key |
| --- | --- |
| Move | `WASD` |
| Wait / search / listen | `Space` |
| Inventory | `I` |
| Character sheet | `C` |
| Use potion / consumables | `H` |
| Fire ranged weapon | `F` |
| Class abilities | `Q` |
| Select / confirm | `Enter` |
| Back / close / pause | `Esc` / `Backspace` depending on panel |
| Debug descend | `Shift+.` or `PageDown` |
| Toggle audio | `M` |

Panels usually accept `W/S` or arrow-key style navigation through Godot UI actions.

## Debug mode

Name your character `debug` to start with a testing loadout:

- 20 in all stats.
- Full item set.
- 9999 gold.
- Debug floor descent shortcuts.

Debug runs are filtered out of the permanent run archive.

## Running locally

Requires **Godot 4.4**.

```sh
/usr/local/bin/godot --path .
```

The main project scene redirects into the main menu:

```text
main.gd -> scenes/main_menu.tscn
```

## Running tests

The project uses headless Godot test scripts under `scripts/tests/`.

Example smoke test:

```sh
/usr/local/bin/godot --headless --path . --script res://scripts/tests/test_shop_scaling.gd
```

Useful focused tests include:

```sh
/usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v15_feeling_upgrade.gd
/usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v16_enemy_intents.gd
/usr/local/bin/godot --headless --path . --script res://scripts/tests/test_v16_5_sensory_settings.gd
```

## Pixel visual assets

Pixel renderer resources are declared explicitly in `assets/visual_assets.json`; all eleven project-authored production visual sources live under `assets/pixel_art/source/`. Validate, release-check, or regenerate the deterministic Godot catalogues with:

```sh
python3 tools/pixel_assets.py check
python3 tools/pixel_assets.py generate
python3 tools/pixel_assets.py release-check
```

Aseprite source conventions, export commands, generated-file rules, and licensing requirements are documented in [`docs/pixel_asset_pipeline.md`](docs/pixel_asset_pipeline.md).

## Pixel renderer release validation

Run the focused renderer, gameplay-parity, accessibility, and startup gates with:

```sh
python3 tools/run_pixel_release_gate.py
```

Optional release-candidate checks:

```sh
# Requires a desktop rendering backend; captures one fixed scene in all three modes.
python3 tools/run_pixel_release_gate.py --visual-capture

# Requires Godot Web export templates.
python3 tools/run_pixel_release_gate.py --web-export
```

The automated release gate enforces these renderer budgets:

- 120 live `ASCII -> Hybrid -> Full Pixel` cycles without actor-view duplication, transient-effect leaks, or more than four residual nodes.
- No more than 16 MiB of retained static-memory growth across that switch stress.
- A fixed 12-emitter particle pool with zero active emitters after renderer reset.
- 64 actors across 60 presentation updates in at most 5 seconds, with no static-tile rebuilds for actor-only changes.
- Identical renderer-neutral state before and after mode changes, transient effects, dense actor updates, and viewport changes.
- Fixed-scene desktop captures that distinguish ASCII from Hybrid and Hybrid from Full Pixel.
- Five viewport sizes from `720x610` through `1600x900`, followed by verified ASCII restoration.

`.github/workflows/visual-assets.yml` runs the focused suite and a clean Web release export for renderer-affecting pull requests and pushes to `main`. Headless CI cannot read rendered textures, so the desktop capture gate remains an explicit release-candidate command.

Reference Web threshold at `1180x760`: at least 55 average FPS with a 25 ms-or-lower p95 frame time during floor transitions, movement, and 90 live renderer changes; the canvas must match every tested viewport and the browser must report no console, page, or resource-load errors.

Hybrid is the default for new players and settings files without an explicit graphics preference. Existing saved preferences remain intact, while ASCII remains the compatibility fallback for invalid values or unavailable pixel resources. Full Pixel Map remains opt-in. Release checks cover all three modes, boss encounters, renderer switching, reduced VFX, viewport resizing, focus return, and browser errors.

## Web export

The repo includes a Web export preset.

```sh
/usr/local/bin/godot --headless --export-release "Web"
```

After exporting, copy the versioned HTML to `build/web/index.html` while preserving the generated asset base in the copied file. The live GitHub Pages deployment serves from the `gh-pages` branch.

## Project map

```text
scripts/
  autoload/       GameManager and Dice singletons
  components/     Stats, inventory, and reusable actor components
  dungeon/        DungeonData and DungeonGenerator
  entities/       Actor, Player, Enemy
  resources/      GDScript resource classes like ItemData and EnemyData
  systems/        Combat, turns, FOV, pathfinding, traps
  ui/             HUD, menus, panels, Library, ASCII backdrop, map view
  tests/          Headless Godot regression scripts

resources/
  enemies/        Enemy and boss .tres resources
  items/          Item .tres resources
  traps/          Trap .tres resources

scenes/           Godot .tscn scenes
assets/audio/     Audio assets, including boss battle tracks
assets/pixel_art/ Production pixel-art atlases and optional generated outputs
assets/*.json     Visual source manifest and generated attribution
fonts/            Terminus and JetBrainsMono font resources
```

## Architecture notes

The project currently centers around `scripts/game.gd`, a large controller that owns floor generation, player input, spawning, shops, containers, status effects, and the main turn loop.

Key singletons:

- `GameManager`: floor state, map data, turn registry, player/enemy references, XP, run history, and global messages.
- `Dice`: d20 rolls, generic rolls, ability score generation, and modifiers.

Important resource path detail:

- Enemy, item, and trap `.tres` paths are hardcoded in `scripts/resource_paths.gd` so the web export can load them reliably. Add new content there or it may work locally and vanish on web.

## Design vibe

Readable first. Stylish second. Mean third.

The dungeon should feel like a board game, a terminal toy, and a bad omen sharing the same chair. If a system adds confusion without adding tension, cut it. If an effect looks cool but hides the tactical state, calm it down. If treasure is glowing in a side room and the player is low on health, perfect.

## Credits / note

Made with **Godot 4.4**.

The mechanics are inspired by tabletop fantasy RPG patterns, especially d20-style combat and ability scores, but this is an original game project and not an official Dungeons & Dragons product.
