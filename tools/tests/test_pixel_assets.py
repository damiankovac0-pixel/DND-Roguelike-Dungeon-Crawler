from __future__ import annotations

import copy
import importlib.util
from pathlib import Path
import unittest


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPOSITORY_ROOT / "tools" / "pixel_assets.py"
SPEC = importlib.util.spec_from_file_location("pixel_assets", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
pixel_assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(pixel_assets)


class PixelAssetPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.manifest = pixel_assets.load_manifest()
        cls.actor_asset = copy.deepcopy(cls.manifest["assets"][1])
        cls.actor_asset.update(
            {
                "source_path": "assets/pixel_art/source/actors.aseprite",
                "source_format": "aseprite",
                "exporter": "aseprite",
                "runtime_path": "assets/pixel_art/generated/actors.png",
                "metadata_path": "assets/pixel_art/generated/actors.json",
            }
        )

    def test_committed_outputs_are_current_and_deterministic(self) -> None:
        pixel_assets.check(self.manifest)
        first = pixel_assets.generated_outputs(self.manifest)
        second = pixel_assets.generated_outputs(self.manifest)
        self.assertEqual(first, second)
        self.assertEqual(len(first), 4)

    def test_production_manifest_passes_readiness(self) -> None:
        errors = pixel_assets.validate_production_readiness(self.manifest)
        self.assertEqual(errors, [])

    def test_production_readiness_rejects_asset_prototype(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["assets"][2]["prototype"] = True
        errors = pixel_assets.validate_production_readiness(mutated)
        self.assertIn("Asset boss/core is still marked prototype", errors)

    def test_production_readiness_rejects_catalogue_prototype(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["catalogs"][1]["prototype"] = True
        errors = pixel_assets.validate_production_readiness(mutated)
        self.assertIn("Catalogue actors is still marked prototype", errors)

    def test_production_readiness_rejects_prototype_path(self) -> None:
        mutated = copy.deepcopy(self.manifest)
        mutated["assets"][0]["source_path"] = "assets/pixel_art/prototype/dungeon_tiles.svg"
        errors = pixel_assets.validate_production_readiness(mutated)
        self.assertTrue(
            any("prototype" in error and "source_path" in error for error in errors),
            f"No path-prototype error found in {errors}",
        )

    def test_actor_export_command_preserves_fixed_grid(self) -> None:
        command = pixel_assets.build_aseprite_command(
            self.manifest,
            self.actor_asset,
            "/opt/aseprite",
        )
        source_index = command.index(str(REPOSITORY_ROOT / self.actor_asset["source_path"]))
        self.assertLess(command.index("--split-layers"), source_index)
        self.assertLess(command.index("--list-layers"), source_index)
        self.assertLess(command.index("--list-tags"), source_index)
        self.assertEqual(command[command.index("--sheet-type") + 1], "rows")
        self.assertEqual(command[command.index("--sheet-columns") + 1], "12")
        self.assertEqual(command[command.index("--sheet-rows") + 1], "14")
        self.assertEqual(command[command.index("--sheet-width") + 1], "192")
        self.assertEqual(command[command.index("--sheet-height") + 1], "224")
        self.assertEqual(command[command.index("--format") + 1], "json-array")
        self.assertNotIn("--trim", command)
        self.assertNotIn("--sheet-pack", command)
        self.assertNotIn("--merge-duplicates", command)

    def test_actor_metadata_requires_every_animation_and_layer(self) -> None:
        metadata = self._actor_metadata()
        pixel_assets.validate_aseprite_metadata(self.actor_asset, metadata)

        missing_tag = copy.deepcopy(metadata)
        missing_tag["meta"]["frameTags"].pop()
        with self.assertRaisesRegex(pixel_assets.PipelineError, "missing animation tag death"):
            pixel_assets.validate_aseprite_metadata(self.actor_asset, missing_tag)

        wrong_layers = copy.deepcopy(metadata)
        wrong_layers["meta"]["layers"][0]["name"] = "enemy"
        with self.assertRaisesRegex(pixel_assets.PipelineError, "layers must match row_ids"):
            pixel_assets.validate_aseprite_metadata(self.actor_asset, wrong_layers)

    def test_actor_metadata_rejects_trimmed_or_wrong_size_frames(self) -> None:
        trimmed = self._actor_metadata()
        trimmed["frames"][0]["trimmed"] = True
        with self.assertRaisesRegex(pixel_assets.PipelineError, "trimmed frames are not supported"):
            pixel_assets.validate_aseprite_metadata(self.actor_asset, trimmed)

        wrong_size = self._actor_metadata()
        wrong_size["meta"]["size"]["w"] = 191
        with self.assertRaisesRegex(pixel_assets.PipelineError, "sheet size is incorrect"):
            pixel_assets.validate_aseprite_metadata(self.actor_asset, wrong_size)

    def test_terrain_manifest_schema(self) -> None:
        """Terrain is a static 12x6 atlas with 72 fully-qualified semantic IDs, no row_ids, no animations.

        Assertions encode the static-atlas contract and catch reintroduction of
        row_ids, fake animations, or fewer than 72 semantic IDs.
        """
        terrain = self.manifest["assets"][0]
        self.assertEqual(terrain["id"], "terrain/core")
        grid = tuple(terrain["grid"])
        total_slots = grid[0] * grid[1]

        # Static atlas: semantic_ids must fill grid, row_ids and animations absent or empty
        self.assertEqual(len(terrain["semantic_ids"]), total_slots)
        self.assertFalse(terrain.get("row_ids", []))       # no row_ids
        self.assertEqual(terrain.get("animations", {}), {})  # no fake animations

        # Manifest validation rejects a semantic-count mismatch
        mutated = copy.deepcopy(self.manifest)
        mutated["assets"][0]["semantic_ids"] = mutated["assets"][0]["semantic_ids"][:total_slots - 1]
        with self.assertRaises(pixel_assets.PipelineError) as ctx:
            pixel_assets._validate_manifest_structure(mutated, REPOSITORY_ROOT)
        self.assertIn("semantic_ids must fill the atlas grid", str(ctx.exception))

    @staticmethod
    def _actor_metadata() -> dict[str, object]:
        frames = []
        for index in range(168):
            frames.append(
                {
                    "filename": f"frame-{index}",
                    "frame": {"x": (index % 12) * 16, "y": (index // 12) * 16, "w": 16, "h": 16},
                    "rotated": False,
                    "trimmed": False,
                    "spriteSourceSize": {"x": 0, "y": 0, "w": 16, "h": 16},
                    "sourceSize": {"w": 16, "h": 16},
                    "duration": 100,
                }
            )
        animation_names = ("idle", "move", "attack", "cast", "hurt", "death")
        return {
            "frames": frames,
            "meta": {
                "app": "https://www.aseprite.org/",
                "version": "1.3.0",
                "image": "actors.png",
                "format": "RGBA8888",
                "size": {"w": 192, "h": 224},
                "scale": "1",
                "frameTags": [
                    {"name": name, "from": index * 2, "to": index * 2 + 1, "direction": "forward"}
                    for index, name in enumerate(animation_names)
                ],
                "layers": [
                    {"name": name}
                    for name in (
                        "player_fighter",
                        "player_ranger",
                        "player_wizard",
                        "enemy_humanoid",
                        "enemy_brute",
                        "enemy_undead",
                        "enemy_beast",
                        "enemy_flyer",
                        "enemy_construct",
                        "enemy_caster",
                        "enemy_aquatic",
                        "enemy_aberration",
                        "shopkeeper",
                        "summon",
                    )
                ],
            },
        }


if __name__ == "__main__":
    unittest.main()
