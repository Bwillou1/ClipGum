#!/usr/bin/env python3
"""Generate a CycloneDX 1.5 SBOM from SwiftPM's resolved dependency pins."""

import argparse
import datetime as dt
import json
import pathlib
import plistlib
import re
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[1]
KNOWN = {
    "mlx-swift": ("MLX Swift", "0.31.3", None, "MIT", "https://github.com/ml-explore/mlx-swift"),
    "mlx-swift-lm": ("MLX Swift LM", "2.31.3", None, "MIT", "https://github.com/ml-explore/mlx-swift-lm"),
    "llama.swift": ("llama.swift", None, "018619bf56f92cc85286150611609f456813826f", "MIT", "https://github.com/mattt/llama.swift"),
    "sparkle": ("Sparkle", "2.10.0", None, "MIT", "https://github.com/sparkle-project/Sparkle"),
}


def resolved_pins():
    path = ROOT / "Package.resolved"
    if not path.exists():
        return {}
    payload = json.loads(path.read_text())
    return {pin["identity"]: pin.get("state", {}) for pin in payload.get("pins", [])}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=pathlib.Path, default=ROOT / "Build/SBOM.json")
    parser.add_argument("--sync-resource", action="store_true")
    args = parser.parse_args()

    pins = resolved_pins()
    plist = plistlib.loads((ROOT / "Resources/Info.plist").read_bytes())
    version = plist["CFBundleShortVersionString"]
    commit = re.sub(r"[^0-9a-f]", "", __import__("subprocess").check_output(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True
    ).strip().lower())
    timestamp = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

    components = []
    refs = []
    for identity, (name, fallback_version, fallback_revision, license_id, url) in KNOWN.items():
        state = pins.get(identity, {})
        resolved_version = state.get("version", fallback_version)
        revision = state.get("revision", fallback_revision)
        purl_version = resolved_version or revision
        purl = f"pkg:github/{url.removeprefix('https://github.com/')}@{purl_version}"
        component = {
            "type": "library",
            "bom-ref": purl,
            "name": name,
            "version": purl_version,
            "licenses": [{"license": {"id": license_id}}],
            "purl": purl,
            "externalReferences": [{"type": "vcs", "url": url}],
        }
        if revision:
            component.setdefault("properties", []).append({"name": "clipgum:gitRevision", "value": revision})
        if identity == "sparkle":
            component["hashes"] = [{
                "alg": "SHA-256",
                "content": "17e28312b8e18ab7cdbbe09a6fb28cc55a5479ec6c371dbc07cdecd2a14fd959",
            }]
        components.append(component)
        refs.append(purl)

    llama_ref = "pkg:github/ggml-org/llama.cpp@b10549"
    components.append({
        "type": "library",
        "bom-ref": llama_ref,
        "name": "llama.cpp",
        "version": "b10549",
        "licenses": [{"license": {"id": "MIT"}}],
        "purl": llama_ref,
        "externalReferences": [{"type": "vcs", "url": "https://github.com/ggml-org/llama.cpp"}],
        "properties": [{"name": "clipgum:distribution", "value": "binary xcframework through llama.swift"}],
    })
    components.append({
        "type": "machine-learning-model",
        "bom-ref": "prismml-ternary-bonsai-external",
        "name": "PrismML Ternary Bonsai",
        "version": "NOASSERTION",
        "scope": "optional",
        "description": "Optional external model family only; no weights are bundled or relicensed by ClipGum.",
        "licenses": [{"license": {"name": "NOASSERTION"}}],
        "properties": [{"name": "clipgum:bundled", "value": "false"}],
    })

    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.5",
        "serialNumber": "urn:uuid:" + str(uuid.uuid5(uuid.NAMESPACE_URL, f"https://github.com/Bwillou1/ClipGum/commit/{commit}")),
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "component": {
                "type": "application",
                "bom-ref": "clipgum",
                "name": "ClipGum",
                "version": version,
                "licenses": [{"license": {"id": "Apache-2.0"}}],
                "externalReferences": [{"type": "vcs", "url": "https://github.com/Bwillou1/ClipGum"}],
            },
            "properties": [
                {"name": "clipgum:gitRevision", "value": commit},
                {"name": "clipgum:platform", "value": "macOS 14+ arm64"},
                {"name": "clipgum:referenceOnly", "value": "Boop and Maccy pattern references; not linked components"},
            ],
        },
        "components": sorted(components, key=lambda item: item["name"].lower()),
        "dependencies": [
            {"ref": "clipgum", "dependsOn": sorted(refs)},
            {"ref": next(ref for ref in refs if "llama.swift" in ref), "dependsOn": [llama_ref]},
        ],
    }
    rendered = json.dumps(bom, indent=2, sort_keys=True) + "\n"
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(rendered)
    if args.sync_resource:
        resource = ROOT / "Sources/ClipGum/UI/Settings/Licenses/Resources/SBOM.json"
        resource.write_text(rendered)
    print(f"Generated {args.output}")


if __name__ == "__main__":
    main()
