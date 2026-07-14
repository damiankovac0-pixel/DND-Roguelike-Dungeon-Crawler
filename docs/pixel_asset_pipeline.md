# Pixel visual asset pipeline

The pixel renderer loads only explicit Godot resources. `assets/visual_assets.json` is the build-time source of truth for visual source files, runtime textures, atlas dimensions, semantic IDs, licences, attribution, and generated `.tres` catalogues. Runtime code never scans asset directories and never invokes Aseprite.

The five currently declared visual sources are project-authored prototype SVGs. They use `"exporter": "committed"`, so the source and runtime texture are the same file. Production art can replace entries incrementally with committed `.aseprite` sources and generated PNG/JSON pairs; the renderer remains playable from committed outputs without Aseprite installed.

## Commands

Run from the repository root:

```sh
# Validate paths, dimensions, animation metadata, hashes, licences, and generated files.
python3 tools/pixel_assets.py check

# Regenerate deterministic .tres catalogues and the attribution record.
python3 tools/pixel_assets.py generate

# Export every Aseprite-backed entry, then regenerate and validate derived files.
ASEPRITE=/absolute/path/to/aseprite python3 tools/pixel_assets.py export

# Show the exact Aseprite commands without changing files.
python3 tools/pixel_assets.py commands --aseprite /absolute/path/to/aseprite

# Pipeline implementation tests.
python3 -m unittest discover -s tools/tests -p 'test_*.py'

# Godot import and runtime-catalogue test.
/usr/local/bin/godot --headless --path . --script \
  res://scripts/tests/test_visual_asset_pipeline.gd
```

`export` resolves Aseprite in this order:

1. The `--aseprite` option.
2. The `ASEPRITE` environment variable.
3. `aseprite` on `PATH`.
4. Standard direct-install and Steam locations on macOS, Windows, and Linux.

Aseprite 1.3.0 or newer is required for Aseprite-backed entries. The command uses the documented batch, sprite-sheet, JSON-array, layer-list, and tag-list options. See the [official Aseprite CLI documentation](https://www.aseprite.org/docs/cli/).

## Repository layout

Current prototype files remain in their established paths:

```text
assets/sprites/prototype/              Project-authored prototype SVG sources/runtime textures
assets/visual_assets.json              Hand-edited source manifest
assets/visual_asset_attribution.json   Generated hashes, paths, licences, and attribution
resources/visuals/catalogs/            Generated explicit Godot Resource catalogues
tools/pixel_assets.py                   Build-time exporter, generator, and validator
tools/tests/test_pixel_assets.py        Build-tool regression coverage
```

Create production files only when real art is ready:

```text
assets/pixel_art/source/terrain/        .aseprite source documents
assets/pixel_art/source/actors/         .aseprite source documents
assets/pixel_art/source/bosses/         .aseprite source documents
assets/pixel_art/source/objects/        .aseprite source documents
assets/pixel_art/source/effects/        .aseprite source documents
assets/pixel_art/generated/             Exported PNG sheets and Aseprite JSON metadata
```

Both source documents and generated runtime outputs are committed. Aseprite is a local/build dependency, never a game or Web-export dependency.

## Source conventions

### Names and IDs

- File and layer names use lowercase `snake_case`.
- Manifest asset and semantic IDs use lowercase path-style names such as `actor/player` and `trap/poison`.
- IDs are stable data contracts. Renaming one requires updating the manifest, the matching runtime catalogue mapping, and every presentation-state producer.
- Runtime and metadata paths are explicit repository-relative paths. Globs, filename construction, and directory enumeration are prohibited.
- Variants use a stable suffix only when the renderer consumes that variant, for example `wall/moss` or `enemy/goblin_elite`. Do not encode transient gameplay state in filenames.

### Dimensions and sheet layout

The current renderer contracts are:

| Content | Frame size | Current sheet grid | Current sheet size |
| --- | ---: | ---: | ---: |
| Terrain | 16×16 | 7×1 | 112×16 |
| Actors | 16×16 | 12×4 | 192×64 |
| Bosses | 80×64 | 12×5 | 960×320 |
| Objects | 16×16 | 16×1 | 256×16 |
| Effect particle | 3×3 | 1×1 | 3×3 |

The manifest requires `expected_size == frame_size * grid`. The exporter fixes sheet rows, columns, width, and height. It deliberately does not trim, rotate, pack, merge duplicate frames, extrude, or add padding. Those operations would invalidate fixed atlas coordinates and pixel-perfect alignment.

For terrain, objects, and effects, put one untrimmed frame at each manifest grid position in `semantic_ids` order.

For actors and bosses:

- One visible Aseprite layer represents each `row_ids` entry, in manifest order.
- Every layer uses the same 12-frame timeline.
- Required tags are `idle`, `move`, `attack`, `cast`, `hurt`, and `death`.
- The current contract assigns two frames to every tag, in that order.
- Tag bounds, layer order, total frame count, frame dimensions, rotation, and trimming are validated from exported JSON.
- Facing remains renderer state; the current generic views mirror sprites where appropriate. Do not add directional sheets until the renderer contract explicitly gains directional animation IDs.

The current runtime builds `SpriteFrames` from fixed atlas regions. Exported Aseprite JSON is build-time validation data, not runtime gameplay data.

### Pixel import rules

- Author at native resolution; do not export scaled sheets.
- Use opaque or clean alpha-edged pixels. Avoid semi-transparent fringe pixels introduced by resampling.
- Godot textures must use nearest-neighbour filtering and disabled mipmaps for map presentation.
- After adding or replacing a PNG, run the Godot editor import once and inspect the generated `.import` settings before committing.
- Keep atlases within the dimensions declared in the manifest. The Python pipeline and runtime catalogue `validate()` methods reject drift.

## Manifest entry types

A committed prototype entry uses the same explicit file as source and runtime output:

```json
{
  "id": "terrain/core",
  "source_path": "assets/sprites/prototype/dungeon_tiles.svg",
  "source_format": "svg",
  "exporter": "committed",
  "runtime_path": "assets/sprites/prototype/dungeon_tiles.svg"
}
```

A production Aseprite entry separates editable source from generated output:

```json
{
  "id": "actor/core",
  "source_path": "assets/pixel_art/source/actors/core.aseprite",
  "source_format": "aseprite",
  "exporter": "aseprite",
  "runtime_path": "assets/pixel_art/generated/actors/core.png",
  "metadata_path": "assets/pixel_art/generated/actors/core.json"
}
```

Keep the remaining contract fields from the replaced entry: `expected_size`, `frame_size`, `grid`, `semantic_ids`, optional `row_ids`, `animations`, `prototype`, `license_id`, and `attribution`. Set `prototype` to `false` only when that catalogue contains approved production art.

## Licence and attribution rules

Every asset references one record in the manifest's `licenses` object and carries non-empty asset-level attribution.

For project-authored work:

- Use `LicenseRef-Project-Authored`.
- Record the repository source URL and rights notice.

Before adding third-party art:

1. Confirm that redistribution and modification are permitted for the game and Web build.
2. Add a distinct licence record with an SPDX identifier when one exists.
3. Record the original author, source URL, licence URL, copyright notice, and required attribution text.
4. Point each applicable asset entry at that licence ID.
5. Run `generate` so `assets/visual_asset_attribution.json` captures the exact runtime file hash.

The current manifest declares no third-party visual assets. Do not reuse audio licensing assumptions for visual files.

## Safe production-art update

1. Add or edit the `.aseprite` source and its manifest entry.
2. Keep semantic IDs, row order, dimensions, and required tags stable unless renderer code changes in the same commit.
3. Run `python3 tools/pixel_assets.py export`.
4. Open Godot once to import changed PNGs; verify nearest-neighbour filtering, mipmaps, and alpha edges.
5. Run `python3 tools/pixel_assets.py check`.
6. Run the Python and Godot pipeline tests.
7. Run the focused pixel renderer tests and a Web release export.
8. Review Hybrid and Full Pixel Map in a browser before committing.
9. Commit source documents, generated PNG/JSON, generated `.tres` catalogues, attribution, and Godot `.import` files together.

Exports are staged in a temporary directory. A failed command, invalid dimension, missing tag, trimmed frame, layer-order mismatch, or malformed metadata is rejected before replacing committed outputs. `check` also fails when catalogues or attribution no longer match the manifest.
