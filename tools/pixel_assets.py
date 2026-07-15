#!/usr/bin/env python3
"""Deterministic build-time export and validation for pixel-map visual assets."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Any, Mapping, Sequence
import xml.etree.ElementTree as ElementTree


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = REPOSITORY_ROOT / "assets" / "visual_assets.json"
ID_PATTERN = re.compile(r"^[a-z0-9]+(?:[._/-][a-z0-9]+)*$")
PROPERTY_PATTERN = re.compile(r"^[a-z][a-z0-9_]*$")
VERSION_PATTERN = re.compile(r"(\d+)\.(\d+)(?:\.(\d+))?")
SUPPORTED_RUNTIME_FORMATS = {"png", "svg"}
SUPPORTED_SOURCE_FORMATS = {"aseprite", "png", "svg"}
SUPPORTED_EXPORTERS = {"aseprite", "committed"}
STANDARD_ASEPRITE_PATHS = (
    "/Applications/Aseprite.app/Contents/MacOS/aseprite",
    "~/Library/Application Support/Steam/steamapps/common/Aseprite/Aseprite.app/Contents/MacOS/aseprite",
    "C:/Program Files/Aseprite/Aseprite.exe",
    "C:/Program Files (x86)/Aseprite/Aseprite.exe",
    "~/.steam/debian-installation/steamapps/common/Aseprite/aseprite",
)


class PipelineError(RuntimeError):
    """A visual-asset contract violation."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PipelineError(message)


def _mapping(value: Any, label: str) -> Mapping[str, Any]:
    _require(isinstance(value, dict), f"{label} must be an object")
    return value


def _list(value: Any, label: str) -> list[Any]:
    _require(isinstance(value, list), f"{label} must be an array")
    return value


def _string(value: Any, label: str, *, allow_empty: bool = False) -> str:
    _require(isinstance(value, str), f"{label} must be a string")
    if not allow_empty:
        _require(bool(value.strip()), f"{label} must not be empty")
    return value


def _positive_pair(value: Any, label: str) -> tuple[int, int]:
    pair = _list(value, label)
    _require(len(pair) == 2, f"{label} must contain exactly two integers")
    _require(
        all(isinstance(component, int) and not isinstance(component, bool) and component > 0 for component in pair),
        f"{label} components must be positive integers",
    )
    return int(pair[0]), int(pair[1])


def _repository_path(relative_path: Any, label: str, root: Path = REPOSITORY_ROOT) -> Path:
    value = _string(relative_path, label)
    _require("\\" not in value, f"{label} must use forward slashes")
    path = PurePosixPath(value)
    _require(not path.is_absolute(), f"{label} must be repository-relative")
    _require(".." not in path.parts, f"{label} must not escape the repository")
    candidate = (root / Path(*path.parts)).resolve()
    try:
        candidate.relative_to(root.resolve())
    except ValueError as error:
        raise PipelineError(f"{label} must remain inside the repository") from error
    return candidate


def _res_path(relative_path: str) -> str:
    return f"res://{relative_path}"


def _read_json(path: Path, label: str) -> Mapping[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise PipelineError(f"{label} is missing: {path}") from error
    except json.JSONDecodeError as error:
        raise PipelineError(f"{label} is not valid JSON: {error}") from error
    return _mapping(value, label)


def load_manifest(path: Path = DEFAULT_MANIFEST, root: Path = REPOSITORY_ROOT) -> Mapping[str, Any]:
    manifest = _read_json(path, "Visual asset manifest")
    _validate_manifest_structure(manifest, root)
    return manifest


def _validate_manifest_structure(manifest: Mapping[str, Any], root: Path) -> None:
    _require(manifest.get("schema_version") == 1, "Visual asset manifest schema_version must be 1")
    catalog_version = manifest.get("catalog_version")
    _require(
        isinstance(catalog_version, int) and not isinstance(catalog_version, bool) and catalog_version > 0,
        "catalog_version must be a positive integer",
    )
    _repository_path(manifest.get("generated_attribution_path"), "generated_attribution_path", root)

    aseprite = _mapping(manifest.get("aseprite"), "aseprite")
    _require(aseprite.get("data_format") == "json-array", "aseprite.data_format must be json-array")
    _require(aseprite.get("sheet_type") == "rows", "aseprite.sheet_type must be rows")
    _string(aseprite.get("minimum_version"), "aseprite.minimum_version")

    licenses = _mapping(manifest.get("licenses"), "licenses")
    _require(bool(licenses), "licenses must not be empty")
    for license_id, license_value in licenses.items():
        _string(license_id, "license id")
        _require(bool(ID_PATTERN.fullmatch(license_id)), f"Invalid license id: {license_id}")
        license_data = _mapping(license_value, f"licenses.{license_id}")
        for field in ("name", "spdx", "copyright_notice", "source_url", "redistribution"):
            _string(license_data.get(field), f"licenses.{license_id}.{field}")
        _string(license_data.get("license_url", ""), f"licenses.{license_id}.license_url", allow_empty=True)
        if not str(license_data["spdx"]).startswith("LicenseRef-Project-Authored"):
            _require(
                bool(str(license_data.get("license_url", "")).strip()),
                f"External license {license_id} requires license_url",
            )

    assets = _list(manifest.get("assets"), "assets")
    _require(bool(assets), "assets must not be empty")
    asset_ids: set[str] = set()
    runtime_paths: set[str] = set()
    assets_by_id: dict[str, Mapping[str, Any]] = {}
    for index, asset_value in enumerate(assets):
        label = f"assets[{index}]"
        asset = _mapping(asset_value, label)
        asset_id = _string(asset.get("id"), f"{label}.id")
        _require(bool(ID_PATTERN.fullmatch(asset_id)), f"Invalid visual asset id: {asset_id}")
        _require(asset_id not in asset_ids, f"Duplicate visual asset id: {asset_id}")
        asset_ids.add(asset_id)
        assets_by_id[asset_id] = asset

        _string(asset.get("category"), f"{label}.category")
        source_path = _string(asset.get("source_path"), f"{label}.source_path")
        runtime_path = _string(asset.get("runtime_path"), f"{label}.runtime_path")
        _repository_path(source_path, f"{label}.source_path", root)
        _repository_path(runtime_path, f"{label}.runtime_path", root)
        _require(runtime_path not in runtime_paths, f"Duplicate runtime_path: {runtime_path}")
        runtime_paths.add(runtime_path)

        source_format = _string(asset.get("source_format"), f"{label}.source_format")
        exporter = _string(asset.get("exporter"), f"{label}.exporter")
        _require(source_format in SUPPORTED_SOURCE_FORMATS, f"Unsupported source format for {asset_id}: {source_format}")
        _require(exporter in SUPPORTED_EXPORTERS, f"Unsupported exporter for {asset_id}: {exporter}")
        if exporter == "aseprite":
            _require(source_format == "aseprite", f"{asset_id}: Aseprite exporter requires an aseprite source")
            _require(source_path != runtime_path, f"{asset_id}: source and runtime paths must differ")
            metadata_path = _string(asset.get("metadata_path"), f"{label}.metadata_path")
            _repository_path(metadata_path, f"{label}.metadata_path", root)
        else:
            _require(source_format in SUPPORTED_RUNTIME_FORMATS, f"{asset_id}: committed source must be png or svg")

        runtime_format = PurePosixPath(runtime_path).suffix.lstrip(".").lower()
        _require(runtime_format in SUPPORTED_RUNTIME_FORMATS, f"{asset_id}: runtime asset must be png or svg")
        size = _positive_pair(asset.get("expected_size"), f"{label}.expected_size")
        frame_size = _positive_pair(asset.get("frame_size"), f"{label}.frame_size")
        grid = _positive_pair(asset.get("grid"), f"{label}.grid")
        _require(
            size == (frame_size[0] * grid[0], frame_size[1] * grid[1]),
            f"{asset_id}: expected_size must equal frame_size multiplied by grid",
        )

        semantic_values = _list(asset.get("semantic_ids"), f"{label}.semantic_ids")
        semantic_ids = [_string(value, f"{label}.semantic_ids") for value in semantic_values]
        _require(bool(semantic_ids), f"{asset_id}: semantic_ids must not be empty")
        _require(len(semantic_ids) == len(set(semantic_ids)), f"{asset_id}: semantic_ids must be unique")
        for semantic_id in semantic_ids:
            _require(bool(ID_PATTERN.fullmatch(semantic_id)), f"{asset_id}: invalid semantic id {semantic_id}")

        animations = _mapping(asset.get("animations"), f"{label}.animations")
        for animation_name, frame_count in animations.items():
            _require(bool(ID_PATTERN.fullmatch(animation_name)), f"{asset_id}: invalid animation name {animation_name}")
            _require(
                isinstance(frame_count, int) and not isinstance(frame_count, bool) and frame_count > 0,
                f"{asset_id}: animation frame counts must be positive integers",
            )
        row_values = asset.get("row_ids", [])
        row_ids = [_string(value, f"{label}.row_ids") for value in _list(row_values, f"{label}.row_ids")]
        _require(len(row_ids) == len(set(row_ids)), f"{asset_id}: row_ids must be unique")
        if row_ids:
            _require(len(row_ids) == grid[1], f"{asset_id}: row_ids count must equal grid height")
            _require(sum(int(value) for value in animations.values()) == grid[0], f"{asset_id}: animation frames must fill each row")
        else:
            _require(len(semantic_ids) == grid[0] * grid[1], f"{asset_id}: semantic_ids must fill the atlas grid")

        _require(isinstance(asset.get("prototype"), bool), f"{asset_id}: prototype must be a boolean")
        license_id = _string(asset.get("license_id"), f"{label}.license_id")
        _require(license_id in licenses, f"{asset_id}: unknown license_id {license_id}")
        _string(asset.get("attribution"), f"{label}.attribution")

    catalogs = _list(manifest.get("catalogs"), "catalogs")
    _require(bool(catalogs), "catalogs must not be empty")
    catalog_ids: set[str] = set()
    catalog_paths: set[str] = set()
    for index, catalog_value in enumerate(catalogs):
        label = f"catalogs[{index}]"
        catalog = _mapping(catalog_value, label)
        catalog_id = _string(catalog.get("id"), f"{label}.id")
        _require(bool(ID_PATTERN.fullmatch(catalog_id)), f"Invalid catalog id: {catalog_id}")
        _require(catalog_id not in catalog_ids, f"Duplicate catalog id: {catalog_id}")
        catalog_ids.add(catalog_id)
        catalog_path = _string(catalog.get("path"), f"{label}.path")
        _repository_path(catalog_path, f"{label}.path", root)
        _require(catalog_path not in catalog_paths, f"Duplicate catalog path: {catalog_path}")
        catalog_paths.add(catalog_path)
        _string(catalog.get("script_class"), f"{label}.script_class")
        _repository_path(catalog.get("script_path"), f"{label}.script_path", root)
        _require(isinstance(catalog.get("prototype"), bool), f"{catalog_id}: prototype must be a boolean")
        _string(catalog.get("attribution"), f"{label}.attribution")
        textures = _list(catalog.get("textures"), f"{label}.textures")
        _require(bool(textures), f"{catalog_id}: textures must not be empty")
        resource_ids: set[str] = set()
        properties: set[str] = set()
        for texture_index, texture_value in enumerate(textures):
            texture_label = f"{label}.textures[{texture_index}]"
            texture = _mapping(texture_value, texture_label)
            property_name = _string(texture.get("property"), f"{texture_label}.property")
            _require(bool(PROPERTY_PATTERN.fullmatch(property_name)), f"Invalid catalog property: {property_name}")
            _require(property_name not in properties, f"{catalog_id}: duplicate texture property {property_name}")
            properties.add(property_name)
            asset_id = _string(texture.get("asset_id"), f"{texture_label}.asset_id")
            _require(asset_id in assets_by_id, f"{catalog_id}: unknown asset_id {asset_id}")
            resource_id = _string(texture.get("resource_id"), f"{texture_label}.resource_id")
            _require(resource_id not in resource_ids, f"{catalog_id}: duplicate resource_id {resource_id}")
            resource_ids.add(resource_id)


def _svg_dimensions(path: Path) -> tuple[int, int]:
    try:
        root = ElementTree.parse(path).getroot()
    except ElementTree.ParseError as error:
        raise PipelineError(f"Invalid SVG {path}: {error}") from error

    def component(name: str) -> int:
        raw = root.get(name, "").strip()
        match = re.fullmatch(r"(\d+)(?:px)?", raw)
        _require(match is not None, f"SVG {path} requires an integer {name}")
        return int(match.group(1))

    return component("width"), component("height")


def _png_dimensions(path: Path) -> tuple[int, int]:
    try:
        with path.open("rb") as stream:
            header = stream.read(24)
    except FileNotFoundError as error:
        raise PipelineError(f"PNG is missing: {path}") from error
    _require(len(header) == 24 and header[:8] == b"\x89PNG\r\n\x1a\n", f"Invalid PNG header: {path}")
    _require(header[12:16] == b"IHDR", f"PNG has no IHDR header: {path}")
    return struct.unpack(">II", header[16:24])


def texture_dimensions(path: Path) -> tuple[int, int]:
    suffix = path.suffix.lower()
    if suffix == ".svg":
        return _svg_dimensions(path)
    if suffix == ".png":
        return _png_dimensions(path)
    raise PipelineError(f"Unsupported runtime texture format: {path}")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_aseprite_metadata(asset: Mapping[str, Any], metadata: Mapping[str, Any]) -> None:
    asset_id = str(asset["id"])
    expected_size = tuple(int(value) for value in asset["expected_size"])
    frame_size = tuple(int(value) for value in asset["frame_size"])
    grid = tuple(int(value) for value in asset["grid"])
    frames_value = metadata.get("frames")
    _require(isinstance(frames_value, (list, dict)), f"{asset_id}: Aseprite metadata frames must be an array or object")
    frames = list(frames_value.values()) if isinstance(frames_value, dict) else frames_value
    _require(len(frames) == grid[0] * grid[1], f"{asset_id}: Aseprite metadata frame count does not match grid")
    for index, frame_value in enumerate(frames):
        frame = _mapping(frame_value, f"{asset_id}.frames[{index}]")
        region = _mapping(frame.get("frame"), f"{asset_id}.frames[{index}].frame")
        source_size = _mapping(frame.get("sourceSize"), f"{asset_id}.frames[{index}].sourceSize")
        _require((region.get("w"), region.get("h")) == frame_size, f"{asset_id}: frame {index} was trimmed or has the wrong size")
        _require((source_size.get("w"), source_size.get("h")) == frame_size, f"{asset_id}: source frame {index} has the wrong size")
        _require(frame.get("rotated") is False, f"{asset_id}: rotated frames are not supported")
        _require(frame.get("trimmed") is False, f"{asset_id}: trimmed frames are not supported")

    meta = _mapping(metadata.get("meta"), f"{asset_id}.meta")
    meta_size = _mapping(meta.get("size"), f"{asset_id}.meta.size")
    _require((meta_size.get("w"), meta_size.get("h")) == expected_size, f"{asset_id}: metadata sheet size is incorrect")
    frame_tags = _list(meta.get("frameTags", []), f"{asset_id}.meta.frameTags")
    tags_by_name: dict[str, Mapping[str, Any]] = {}
    for tag_value in frame_tags:
        tag = _mapping(tag_value, f"{asset_id}.meta.frameTags")
        name = _string(tag.get("name"), f"{asset_id}.meta.frameTags.name")
        _require(name not in tags_by_name, f"{asset_id}: duplicate animation tag {name}")
        tags_by_name[name] = tag
    animations = _mapping(asset.get("animations", {}), f"{asset_id}.animations")
    for animation_name, frame_count_value in animations.items():
        _require(animation_name in tags_by_name, f"{asset_id}: missing animation tag {animation_name}")
        tag = tags_by_name[animation_name]
        start = tag.get("from")
        end = tag.get("to")
        _require(isinstance(start, int) and isinstance(end, int), f"{asset_id}: tag {animation_name} has invalid bounds")
        _require(end - start + 1 == int(frame_count_value), f"{asset_id}: tag {animation_name} has the wrong frame count")
    row_ids = [str(value) for value in asset.get("row_ids", [])]
    if row_ids:
        layer_values = _list(meta.get("layers", []), f"{asset_id}.meta.layers")
        layer_names = [_string(_mapping(value, f"{asset_id}.meta.layers").get("name"), f"{asset_id}.meta.layers.name") for value in layer_values]
        _require(layer_names == row_ids, f"{asset_id}: Aseprite layers must match row_ids in manifest order")


def _validate_files(manifest: Mapping[str, Any], root: Path) -> None:
    for asset_value in manifest["assets"]:
        asset = _mapping(asset_value, "asset")
        asset_id = str(asset["id"])
        source_path = _repository_path(asset["source_path"], f"{asset_id}.source_path", root)
        runtime_path = _repository_path(asset["runtime_path"], f"{asset_id}.runtime_path", root)
        _require(source_path.is_file(), f"{asset_id}: source asset is missing: {source_path}")
        _require(runtime_path.is_file(), f"{asset_id}: runtime asset is missing: {runtime_path}")
        dimensions = texture_dimensions(runtime_path)
        expected_size = tuple(int(value) for value in asset["expected_size"])
        _require(dimensions == expected_size, f"{asset_id}: expected {expected_size[0]}x{expected_size[1]}, found {dimensions[0]}x{dimensions[1]}")
        if asset["exporter"] == "aseprite":
            metadata_path = _repository_path(asset["metadata_path"], f"{asset_id}.metadata_path", root)
            metadata = _read_json(metadata_path, f"{asset_id} Aseprite metadata")
            validate_aseprite_metadata(asset, metadata)

    for catalog_value in manifest["catalogs"]:
        catalog = _mapping(catalog_value, "catalog")
        script_path = _repository_path(catalog["script_path"], f"{catalog['id']}.script_path", root)
        _require(script_path.is_file(), f"{catalog['id']}: catalog script is missing: {script_path}")


def _asset_map(manifest: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
    return {str(asset["id"]): _mapping(asset, "asset") for asset in manifest["assets"]}


def render_catalog(manifest: Mapping[str, Any], catalog: Mapping[str, Any]) -> str:
    assets_by_id = _asset_map(manifest)
    textures = [_mapping(value, "catalog texture") for value in catalog["textures"]]
    lines = [
        f'[gd_resource type="Resource" script_class="{catalog["script_class"]}" load_steps={2 + len(textures)} format=3]',
        "",
        f'[ext_resource type="Script" path="{_res_path(str(catalog["script_path"]))}" id="1_catalog"]',
    ]
    for texture in textures:
        asset = assets_by_id[str(texture["asset_id"])]
        lines.append(
            f'[ext_resource type="Texture2D" path="{_res_path(str(asset["runtime_path"]))}" id="{texture["resource_id"]}"]'
        )
    lines.extend(("", "[resource]", 'script = ExtResource("1_catalog")'))
    lines.append(f'catalog_version = {int(manifest["catalog_version"])}')
    for texture in textures:
        lines.append(f'{texture["property"]} = ExtResource("{texture["resource_id"]}")')
    lines.append(f'prototype = {str(bool(catalog["prototype"])).lower()}')
    lines.append(f'attribution = {json.dumps(str(catalog["attribution"]), ensure_ascii=False)}')
    return "\n".join(lines) + "\n"


def render_attribution(manifest: Mapping[str, Any], root: Path = REPOSITORY_ROOT) -> str:
    licenses = _mapping(manifest["licenses"], "licenses")
    records: list[dict[str, Any]] = []
    for asset_value in sorted(manifest["assets"], key=lambda value: str(value["id"])):
        asset = _mapping(asset_value, "asset")
        runtime_path = _repository_path(asset["runtime_path"], f"{asset['id']}.runtime_path", root)
        records.append(
            {
                "attribution": asset["attribution"],
                "category": asset["category"],
                "frame_size": asset["frame_size"],
                "id": asset["id"],
                "license_id": asset["license_id"],
                "prototype": asset["prototype"],
                "runtime_path": _res_path(str(asset["runtime_path"])),
                "sha256": _sha256(runtime_path),
                "size": asset["expected_size"],
                "source_format": asset["source_format"],
                "source_path": str(asset["source_path"]),
            }
        )
    value = {
        "assets": records,
        "generated_by": "tools/pixel_assets.py",
        "licenses": licenses,
        "schema_version": int(manifest["schema_version"]),
    }
    return json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def generated_outputs(manifest: Mapping[str, Any], root: Path = REPOSITORY_ROOT) -> dict[Path, str]:
    outputs: dict[Path, str] = {}
    for catalog_value in manifest["catalogs"]:
        catalog = _mapping(catalog_value, "catalog")
        path = _repository_path(catalog["path"], f"{catalog['id']}.path", root)
        outputs[path] = render_catalog(manifest, catalog)
    attribution_path = _repository_path(manifest["generated_attribution_path"], "generated_attribution_path", root)
    outputs[attribution_path] = render_attribution(manifest, root)
    return outputs


def _write_atomic(path: Path, content: str) -> bool:
    if path.is_file() and path.read_text(encoding="utf-8") == content:
        return False
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as stream:
        stream.write(content)
        temporary_path = Path(stream.name)
    os.replace(temporary_path, path)
    return True


def generate(manifest: Mapping[str, Any], root: Path = REPOSITORY_ROOT) -> list[Path]:
    _validate_files(manifest, root)
    changed: list[Path] = []
    for path, content in generated_outputs(manifest, root).items():
        if _write_atomic(path, content):
            changed.append(path)
    return changed


def check(manifest: Mapping[str, Any], root: Path = REPOSITORY_ROOT) -> None:
    _validate_files(manifest, root)
    stale: list[Path] = []
    for path, expected in generated_outputs(manifest, root).items():
        if not path.is_file() or path.read_text(encoding="utf-8") != expected:
            stale.append(path)
    if stale:
        relative_paths = ", ".join(str(path.relative_to(root)) for path in stale)
        raise PipelineError(f"Generated visual asset files are stale: {relative_paths}. Run generate or export.")


def validate_production_readiness(manifest: Mapping[str, Any]) -> list[str]:
    """Return sorted error strings for every asset/catalogue still marked prototype
    or whose source/runtime/catalog path contains a ``prototype`` path component."""
    errors: list[str] = []

    for asset_value in manifest["assets"]:
        asset = _mapping(asset_value, "asset")
        asset_id = str(asset["id"])
        if asset.get("prototype", True) is not False:
            errors.append(f"Asset {asset_id} is still marked prototype")
        for path_key in ("source_path", "runtime_path"):
            path_str = str(asset.get(path_key, ""))
            if "prototype" in PurePosixPath(path_str).parts:
                errors.append(
                    f"Asset {asset_id} {path_key} contains a prototype component: {path_str}"
                )

    for catalog_value in manifest["catalogs"]:
        catalog = _mapping(catalog_value, "catalog")
        catalog_id = str(catalog["id"])
        if catalog.get("prototype", True) is not False:
            errors.append(f"Catalogue {catalog_id} is still marked prototype")
        catalog_path = str(catalog.get("path", ""))
        if "prototype" in PurePosixPath(catalog_path).parts:
            errors.append(
                f"Catalogue {catalog_id} path contains a prototype component: {catalog_path}"
            )

    errors.sort()
    return errors


def release_check(manifest: Mapping[str, Any], root: Path = REPOSITORY_ROOT) -> None:
    """Run generated-file check, then production-readiness validation."""
    check(manifest, root)
    errors = validate_production_readiness(manifest)
    if errors:
        raise PipelineError(
            "Production readiness violations:\n  " + "\n  ".join(errors)
        )
    total = len(manifest["assets"])
    print(f"All {total} visual assets are production-ready")


def resolve_aseprite(explicit_path: str | None = None) -> Path:
    candidates: list[str] = []
    if explicit_path:
        candidates.append(explicit_path)
    environment_path = os.environ.get("ASEPRITE")
    if environment_path:
        candidates.append(environment_path)
    discovered = shutil.which("aseprite")
    if discovered:
        candidates.append(discovered)
    candidates.extend(STANDARD_ASEPRITE_PATHS)
    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path.is_file() and (os.name == "nt" or os.access(path, os.X_OK)):
            return path.resolve()
    raise PipelineError("Aseprite CLI was not found. Set ASEPRITE or pass --aseprite with the executable path.")


def _version_tuple(value: str) -> tuple[int, int, int]:
    match = VERSION_PATTERN.search(value)
    _require(match is not None, f"Unable to parse Aseprite version: {value.strip()}")
    return int(match.group(1)), int(match.group(2)), int(match.group(3) or 0)


def validate_aseprite_version(binary: Path, minimum_version: str) -> str:
    result = subprocess.run(
        [str(binary), "--version"],
        check=True,
        capture_output=True,
        text=True,
    )
    version_output = (result.stdout or result.stderr).strip()
    _require(_version_tuple(version_output) >= _version_tuple(minimum_version), f"Aseprite {minimum_version} or newer is required; found {version_output}")
    return version_output


def build_aseprite_command(
    manifest: Mapping[str, Any],
    asset: Mapping[str, Any],
    binary: Path | str,
    root: Path = REPOSITORY_ROOT,
    *,
    output_path: Path | None = None,
    metadata_path: Path | None = None,
) -> list[str]:
    _require(asset.get("exporter") == "aseprite", f"{asset.get('id', 'asset')}: not an Aseprite export")
    source = _repository_path(asset["source_path"], f"{asset['id']}.source_path", root)
    output = output_path or _repository_path(asset["runtime_path"], f"{asset['id']}.runtime_path", root)
    metadata = metadata_path or _repository_path(asset["metadata_path"], f"{asset['id']}.metadata_path", root)
    grid = tuple(int(value) for value in asset["grid"])
    size = tuple(int(value) for value in asset["expected_size"])
    command = [str(binary), "--batch", "--list-tags"]
    if asset.get("row_ids"):
        command.extend(("--split-layers", "--list-layers"))
    command.extend(
        (
            str(source),
            "--sheet-type",
            str(manifest["aseprite"]["sheet_type"]),
            "--sheet-columns",
            str(grid[0]),
            "--sheet-rows",
            str(grid[1]),
            "--sheet-width",
            str(size[0]),
            "--sheet-height",
            str(size[1]),
            "--format",
            str(manifest["aseprite"]["data_format"]),
            "--sheet",
            str(output),
            "--data",
            str(metadata),
        )
    )
    return command


def export_aseprite_assets(
    manifest: Mapping[str, Any],
    root: Path = REPOSITORY_ROOT,
    explicit_binary: str | None = None,
) -> tuple[int, str | None]:
    export_assets = [_mapping(asset, "asset") for asset in manifest["assets"] if asset["exporter"] == "aseprite"]
    if not export_assets:
        generate(manifest, root)
        return 0, None
    binary = resolve_aseprite(explicit_binary)
    version = validate_aseprite_version(binary, str(manifest["aseprite"]["minimum_version"]))
    exported_count = 0
    for asset in export_assets:
        asset_id = str(asset["id"])
        source_path = _repository_path(asset["source_path"], f"{asset_id}.source_path", root)
        _require(source_path.is_file(), f"{asset_id}: Aseprite source is missing: {source_path}")
        runtime_path = _repository_path(asset["runtime_path"], f"{asset_id}.runtime_path", root)
        metadata_path = _repository_path(asset["metadata_path"], f"{asset_id}.metadata_path", root)
        runtime_path.parent.mkdir(parents=True, exist_ok=True)
        metadata_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="pixel-assets-", dir=runtime_path.parent) as temporary_directory:
            temporary_root = Path(temporary_directory)
            staged_runtime = temporary_root / runtime_path.name
            staged_metadata = temporary_root / metadata_path.name
            command = build_aseprite_command(
                manifest,
                asset,
                binary,
                root,
                output_path=staged_runtime,
                metadata_path=staged_metadata,
            )
            result = subprocess.run(command, capture_output=True, text=True)
            if result.returncode != 0:
                detail = (result.stderr or result.stdout).strip()
                raise PipelineError(f"{asset_id}: Aseprite export failed: {detail}")
            _require(staged_runtime.is_file(), f"{asset_id}: Aseprite did not create the sprite sheet")
            _require(staged_metadata.is_file(), f"{asset_id}: Aseprite did not create metadata")
            dimensions = texture_dimensions(staged_runtime)
            expected_size = tuple(int(value) for value in asset["expected_size"])
            _require(dimensions == expected_size, f"{asset_id}: exported sprite sheet dimensions are incorrect")
            metadata = _read_json(staged_metadata, f"{asset_id} staged Aseprite metadata")
            validate_aseprite_metadata(asset, metadata)
            os.replace(staged_runtime, runtime_path)
            os.replace(staged_metadata, metadata_path)
            exported_count += 1
    generate(manifest, root)
    return exported_count, version


def _print_commands(manifest: Mapping[str, Any], root: Path, binary: str) -> int:
    count = 0
    for asset_value in manifest["assets"]:
        asset = _mapping(asset_value, "asset")
        if asset["exporter"] != "aseprite":
            continue
        print(subprocess.list2cmdline(build_aseprite_command(manifest, asset, binary, root)))
        count += 1
    return count


def _parse_arguments(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST, help="visual asset manifest path")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("check", help="validate assets and require generated files to be current")
    subparsers.add_parser("generate", help="regenerate Godot catalogues and attribution records")
    export_parser = subparsers.add_parser("export", help="export Aseprite sources and regenerate derived files")
    export_parser.add_argument("--aseprite", help="path to the Aseprite executable")
    commands_parser = subparsers.add_parser("commands", help="print deterministic Aseprite commands without running them")
    commands_parser.add_argument("--aseprite", default="${ASEPRITE}", help="executable shown in commands")
    subparsers.add_parser("release-check", help="run check plus production-readiness validation")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    arguments = _parse_arguments(argv or sys.argv[1:])
    manifest_path = arguments.manifest.resolve()
    manifest = load_manifest(manifest_path, REPOSITORY_ROOT)
    if arguments.command == "check":
        check(manifest, REPOSITORY_ROOT)
        print(f"Visual asset pipeline valid: {len(manifest['assets'])} assets, {len(manifest['catalogs'])} catalogues")
    elif arguments.command == "generate":
        changed = generate(manifest, REPOSITORY_ROOT)
        if changed:
            for path in changed:
                print(f"Generated {path.relative_to(REPOSITORY_ROOT)}")
        else:
            print("Visual asset generated files already current")
    elif arguments.command == "release-check":
        release_check(manifest, REPOSITORY_ROOT)
    elif arguments.command == "export":
        count, version = export_aseprite_assets(manifest, REPOSITORY_ROOT, arguments.aseprite)
        if count:
            print(f"Exported {count} Aseprite assets with {version}")
        else:
            print("No Aseprite-backed assets yet; validated committed production sources")
    elif arguments.command == "commands":
        count = _print_commands(manifest, REPOSITORY_ROOT, arguments.aseprite)
        if not count:
            print("No Aseprite-backed assets are declared")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PipelineError, OSError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        raise SystemExit(1) from error
