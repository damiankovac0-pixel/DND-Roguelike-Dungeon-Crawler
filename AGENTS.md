# Dungeon Delver - Godot 4.4 ASCII Roguelike

## Project Structure
- `scripts/` - All GDScript source files
- `scripts/autoload/` - Global singletons (GameManager, Dice)
- `scripts/components/` - Reusable components (StatsComponent, Inventory)
- `scripts/dungeon/` - Dungeon generation (DungeonGenerator, DungeonData)
- `scripts/entities/` - Actor, Player, Enemy scripts
- `scripts/systems/` - TurnManager, CombatSystem, FOVSystem, Pathfinding
- `scripts/ui/` - HUD, MessageLog, MainMenu, GameOver
- `scenes/` - Godot scene files (.tscn)
- `resources/` - Resource files (.tres)
- `fonts/` - Terminus font

## Conventions
- Use explicit type hints on all variables and function signatures
- Use `snake_case` for variables/functions, `PascalCase` for classes
- Order by: signals, enums, exports, constants, public vars, private vars, onready, lifecycle, public methods, private methods
- Use `@onready var x: Type = $Path` for node references
- Prefer signal-up, call-down architecture
- Run `gdlint` and `gdformat` before committing

## MCP Tool
- The `godot` MCP server is configured for scene/node manipulation
- Use `mcp__godot__*` tools to create/modify scenes

## Godot MCP Reference
- `mcp__godot__create_scene(path)` - Create new scene file
- `mcp__godot__add_node(scene_path, parent_path, node_type, name)` - Add node to scene
- `mcp__godot__save_scene(path)` - Save scene
- `mcp__godot__load_sprite(path)` - Load texture resource

## Web Deployment
- Export preset: `export_presets.cfg` — preset name "Web", platform "Web", output `build/web/index.html`
- Export command: `godot --export-release "Web"`
- Repo: `damiankovac0-pixel/DND-Roguelike-Dungeon-Crawler`
- Live URL: https://damiankovac0-pixel.github.io/DND-Roguelike-Dungeon-Crawler/
- GitHub Pages serves from `gh-pages` branch (root `/`)

### Update web build (after re-exporting):
```sh
git checkout gh-pages && git rm -rf . && cp -r build/web/* . && git add -A && git commit -m "Update web build" && git push origin gh-pages && git checkout main
```
