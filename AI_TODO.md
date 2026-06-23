# Dungeon Adventurer MVP — Implementation Checklist

## Setup & Assets
- [ ] Create font resource and base scenes (main.tscn, game.tscn, main_menu.tscn, game_over.tscn, victory.tscn)

## Core Systems (autoloads)
- [ ] Implement Dice autoload (d20, roll, 4d6 drop lowest)
- [ ] Implement GameManager autoload (global state, XP, leveling)

## Dungeon
- [ ] Implement DungeonData and DungeonGenerator (BSP rooms, tile placement)

## Entities
- [ ] Implement Actor base class and StatsComponent
- [ ] Implement Player.gd (input, movement, bump combat)
- [ ] Implement Enemy.gd (AI, pathfinding, basic behavior)

## Systems
- [ ] Implement CombatSystem (d20 attack, damage, crit, XP)
- [ ] Implement FOVSystem and Pathfinding
- [ ] Implement TurnManager (player action → enemy phase)

## UI
- [ ] Implement UI: HUD, MessageLog, Inventory, CharacterSheet

## Items & Resources
- [ ] Implement items (Health Potion, Longsword, Chainmail) and Inventory component
- [ ] Create enemy resources (goblin, skeleton, rat .tres files)
- [ ] Create item resources (health_potion, longsword, chainmail .tres files)
- [ ] Implement stairs/descend logic and victory/game-over scenes

## Polish
- [ ] Run gdlint + gdformat on all scripts, verify game boots
