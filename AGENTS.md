# Dungeon Delver - Godot 4.4 ASCII Roguelike

## Architecture Overview

### Scene Flow
```
main_menu.tscn  →  character_creation.tscn  →  game.tscn  →  end_screen.tscn
                                                           ↺ (retry → game.tscn)
```
`main.gd` is the project's run-main-scene bootstrapper — it just redirects to `main_menu.tscn`.

### Autoloads (global singletons)
- **GameManager** (`scripts/autoload/game_manager.gd`) — floor state, turn order, player/enemy registry, XP, run history, signals. Everything reads/writes `GameManager.current_floor`.
- **Dice** (`scripts/autoload/dice.gd`) — `d20()`, `roll(sides)`, `roll_4d6_drop_lowest()`, `modifier(score)`.

### Core Game Loop (game.gd)
`scripts/game.gd` is the monolithic controller (~2600 lines). It owns:
1. **Floor generation** — calls `DungeonGenerator.generate(width, height, floor_number)`, then spawns enemies, items, traps, containers, shopkeeper.
2. **Player input** — `_unhandled_input()` handles movement, attack bump, wait, dash, targeting.
3. **Turn order** — player acts → `TurnManager.run_enemy_phase()` → enemies act via `Pathfinding` + `CombatSystem`.
4. **Combat** — `CombatSystem.attack()` resolves d20 vs AC; damage types use `*_damage_percent` from `EnemyData`.
5. **Shop** — shopkeeper NPC; `_generate_shop_stock(floor)` scales offers by floor depth; buy/sell/reroll via `ShopPanel` signals.
6. **Containers** — chests (rarity-scaled loot) and clutter (gold/potions/XP orbs).
7. **Status effects** — shield, haste, regen, poison, dash charge — all tracked as instance vars on game.gd.

### Key Data Flow
```
EnemyData.tres  →  Enemy.initialize_from_data()  →  StatsComponent.configure_enemy()
ItemData.tres   →  InventoryComponent.add_item()  →  equipped via inventory_panel
DungeonGenerator  →  Dictionary result {map, rooms, spawns, ...}  →  game.gd spawns entities
game.gd  →  GameManager.set_map_data()  →  MapView draws grid
game.gd  →  GameManager.add_log_message()  →  MessageLog displays colored text
```

### Floor Scaling
- **Enemies**: `_scale_enemy_for_floor()` adds HP, AC, attack, damage, XP per depth.
- **Items**: `_get_item_candidates_for_floor()` gates by `min_floor`/`max_floor`; `_rarity_weight_for_floor()` shifts rarity odds with depth.
- **Shop**: `_get_effective_shop_floor()` boosts selection floor; `_get_shop_minimum_rarity()` raises rarity floor at depth 6/10/14; stock size grows from 6→9.
- **Chests**: `_choose_chest_rarity()` uses depth-weighted rarity; rewards use `floor + chest_rarity * 2` as effective floor.
- **Gold**: enemy gold rewards scale with `current_floor`; chest gold scales with `floor * 2-5 + rarity * 12-28`.

### Debug Mode
- Character name `"debug"` grants 20 in all stats, full item set, 9999 gold.
- `Shift+>` or `PageDown` (or pause-menu button) descends one floor instantly.
- Debug runs are filtered from the run archive.

### Resource Paths
Item/enemy/trap `.tres` paths are hardcoded in `scripts/resource_paths.gd` (`class_name ResourcePaths`) because DirAccess doesn't work in web exports. When adding new resources, append their paths to `ResourcePaths.ENEMY_PATHS`, `ResourcePaths.ITEM_PATHS`, or `ResourcePaths.TRAP_PATHS`. Both `game.gd` and `library_menu.gd` reference these — updating one file updates both.

## Project Structure
- `scripts/` - All GDScript source files
- `scripts/autoload/` - Global singletons (GameManager, Dice)
- `scripts/components/` - Reusable components (StatsComponent, InventoryComponent)
- `scripts/dungeon/` - Dungeon generation (DungeonGenerator, DungeonData)
- `scripts/entities/` - Actor (base), Player, Enemy
- `scripts/systems/` - TurnManager, CombatSystem, FOVSystem, Pathfinding, TrapSystem
- `scripts/ui/` - HUD, MessageLog, MainMenu, EndScreen, ShopPanel, InventoryPanel, CharacterSheet, CharacterCreation, LevelUpPanel, ConsumablePanel, LibraryMenu, AsciiBackdrop, MapView
- `scripts/resource_paths.gd` - Hardcoded resource path constants (shared by game.gd and library_menu.gd)
- `scripts/tests/` - Headless test harness (run with `godot --headless --path . --script`)
- `scenes/` - Godot scene files (.tscn)
- `resources/` - Resource files (.tres); `resources/items/`, `resources/enemies/`, `resources/traps/`
- `fonts/` - Terminus and JetBrainsMono fonts

## Conventions
- Use explicit type hints on all variables and function signatures
- Use `snake_case` for variables/functions, `PascalCase` for classes
- Order by: signals, enums, exports, constants, public vars, private vars, onready, lifecycle, public methods, private methods
- Use `@onready var x: Type = $Path` for node references
- Prefer signal-up, call-down architecture
- Run `gdformat` before committing (installed via `uv tool install gdtoolkit==4.5.0`)
- Run `gdlint` to check style (note: `game.gd` exceeds `max-file-lines` by design; other warnings are pre-existing)
- Run tests: `/usr/local/bin/godot --headless --path . --script res://scripts/tests/test_shop_scaling.gd`
- `game.gd` has `# ===== Section Name =====` markers — `grep "# =====" scripts/game.gd` gives a table of contents

## MCP Tool
- The `godot` MCP server is configured for scene/node manipulation
- Use `mcp__godot__*` tools to create/modify scenes

## Godot MCP Reference
- `mcp__godot__create_scene(path)` - Create new scene file
- `mcp__godot__add_node(scene_path, parent_path, node_type, name)` - Add node to scene
- `mcp__godot__save_scene(path)` - Save scene
- `mcp__godot__load_sprite(path)` - Load texture resource

## Web Deployment
- Export preset: `export_presets.cfg` — preset name "Web", platform "Web", versioned output currently `build/web/dungeon_delver_web_v9_96.html`
- Export command: `/usr/local/bin/godot --headless --export-release "Web"`
- After exporting, copy the versioned HTML to `build/web/index.html`; keep the versioned asset base (`dungeon_delver_web_v9_96`) inside the copied HTML.
- Repo: `damiankovac0-pixel/DND-Roguelike-Dungeon-Crawler`
- Live URL: https://damiankovac0-pixel.github.io/DND-Roguelike-Dungeon-Crawler/
- GitHub Pages serves from `gh-pages` branch (root `/`)

### Update web build (after re-exporting from `main`):
```sh
rm -rf build .godot
mkdir -p build/web
/usr/local/bin/godot --headless --export-release "Web"
cp build/web/dungeon_delver_web_v9_96.html build/web/index.html
rm -rf /tmp/dnd-v9-96-web
cp -R build/web /tmp/dnd-v9-96-web
git add -A
git commit -m "Prepare v9.96 quality-of-life update"
git push origin main
git checkout gh-pages
git rm -r --ignore-unmatch .
cp -R /tmp/dnd-v9-96-web/* .
git add -A
git commit -m "Deploy v9.96 web build"
git push origin gh-pages
git checkout main
```
