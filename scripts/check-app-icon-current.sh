#!/usr/bin/env python3
"""Refuse a committed icon catalog that its source artwork does not produce.

ovation#102. `Ovation/Assets.xcassets/AppIcon.appiconset` is DERIVED from
`icon/ovation-app-icon.png` by `scripts/build-app-icon.sh`, and both the source
and the generated result are committed. Nothing asserted they were still in step.

TWO WAYS IT GOES WRONG, BOTH SILENT. The artwork is replaced and the script is
not re-run, so the app ships the previous icon while the repository shows the
new one. Or one of the ten generated PNGs is edited or replaced by hand, so the
shipped icon is something no source in the repository produces.
`scripts/test-built-bundle-icon.sh` passes in both cases: it asserts the bundle
carries a full size icon, never that the icon is the one the artwork specifies.
A generated file committed beside its source is a standing claim that it is
current, and nothing enforced that claim (L422, L405, L336).

IT COMPARES DECODED PIXELS, NOT BYTES, and that was measured rather than
assumed. Regenerated on this machine with Pillow 12.2.0 the catalog comes back
byte for byte identical, which is the only version anybody has measured, so byte
equality would be a guard resting on a fact nobody has established across the
versions it will actually meet (L177). A PNG encoder that changes its filter
choice or its zlib level writes different bytes for the same image, and a guard
that goes red on a dependency upgrade is a standing red, which makes every other
failure in the list unreadable (L538). Pixels answer the question that matters:
is the icon that SHIPS the one the artwork produces. Byte equality is reported
beside the verdict as information, never as the verdict.

`Contents.json` IS compared exactly, because it is JSON the script writes rather
than an encoder's output, and a changed size or filename there is a real change.

IT WRITES NOWHERE NEAR THE COMMITTED CATALOG. The derivation is run into a
throwaway directory through the builder's own seam, because a check that
overwrites the thing it is checking destroys good state before its replacement
is verified (L5). If it went red after clobbering, the evidence would be gone.

A MISSING PILLOW IS "CANNOT MEASURE", NOT A PASS AND NOT A FAILURE. The catalog
is committed precisely so a machine without Pillow can still build the app, so
such a machine is expected, and a red there is indistinguishable from a real one
(L411, L98).

Seams: OVATION_ICON_SOURCE, OVATION_ICON_CATALOG, OVATION_ICON_BUILDER.

Exit codes, one per outcome (L11):
    0  the committed catalog is what the artwork produces
    1  it is not: the artwork moved on, or a generated file was changed by hand
    2  nothing could be measured: no artwork, no catalog, no Pillow, no builder
"""
import filecmp
import json
import os
import shutil
import subprocess
import sys
import tempfile


def main():
    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    source = os.environ.get("OVATION_ICON_SOURCE") or os.path.join(
        repo_root, "icon", "ovation-app-icon.png")
    catalog = os.environ.get("OVATION_ICON_CATALOG") or os.path.join(
        repo_root, "Ovation", "Assets.xcassets", "AppIcon.appiconset")
    builder = os.environ.get("OVATION_ICON_BUILDER") or os.path.join(
        repo_root, "scripts", "build-app-icon.sh")

    if not os.path.isfile(source):
        print(f"CANNOT MEASURE: the source artwork is not at {source}.")
        print("                There is nothing to derive the catalog from.")
        return 2
    if not os.path.isdir(catalog):
        print(f"CANNOT MEASURE: no catalog at {catalog}.")
        print("                That is not a pass: there is nothing to compare.")
        return 2
    if not os.path.isfile(builder):
        print(f"CANNOT MEASURE: the builder is not at {builder}.")
        return 2
    try:
        import PIL.Image  # noqa: F401
    except ImportError:
        print("CANNOT MEASURE: Pillow is not installed, so the catalog cannot be")
        print("                reproduced here. That is neither a pass nor a failure:")
        print("                the catalog is committed precisely so a machine without")
        print("                Pillow can still build the app. Install it to check:")
        print("                    python3 -m pip install --user Pillow")
        return 2

    with tempfile.TemporaryDirectory(prefix="ovation-icon-") as work:
        rebuilt = os.path.join(work, "AppIcon.appiconset")
        environment = dict(os.environ)
        environment["OVATION_ICON_SOURCE"] = source
        environment["OVATION_ICONSET_OUT"] = rebuilt
        run = subprocess.run(["bash", builder], cwd=repo_root, env=environment,
                             capture_output=True, text=True)
        if run.returncode != 0 or not os.path.isdir(rebuilt):
            print("CANNOT MEASURE: the builder refused, so nothing was compared.")
            for line in (run.stdout + run.stderr).strip().splitlines()[:6]:
                print(f"                {line}")
            return 2

        return compare(catalog, rebuilt)


def compare(catalog, rebuilt):
    committed = set(os.listdir(catalog))
    produced = set(os.listdir(rebuilt))

    problems = []
    for name in sorted(produced - committed):
        problems.append((name, "the artwork produces this and the catalog does not have it"))
    for name in sorted(committed - produced):
        problems.append((name, "the catalog carries this and the artwork produces no such file"))

    identical_bytes = 0
    for name in sorted(committed & produced):
        left = os.path.join(catalog, name)
        right = os.path.join(rebuilt, name)
        if filecmp.cmp(left, right, shallow=False):
            identical_bytes += 1
            continue
        if name.lower().endswith(".json"):
            problems.append((name, describe_json(left, right)))
            continue
        if name.lower().endswith(".png"):
            difference = describe_pixels(left, right)
            if difference:
                problems.append((name, difference))
            continue
        problems.append((name, "differs from what the artwork produces"))

    shared = len(committed & produced)
    if problems:
        print(f"STALE: the committed icon catalog is not what {len(produced)} file(s) "
              "of derivation produce.")
        for name, why in problems:
            print(f"  {name}: {why}")
        print("Either the artwork changed and scripts/build-app-icon.sh was not re-run,")
        print("or a generated file was edited by hand, in which case the shipped icon is")
        print("something no source in this repository produces. Run:")
        print("    bash scripts/build-app-icon.sh")
        return 1

    print(f"OK: {shared} file(s) in the catalog, every one the pixels the artwork "
          "produces.")
    print(f"    {identical_bytes} of {shared} were also identical byte for byte, which "
          "is information about this machine's PNG encoder, not the verdict.")
    return 0


def describe_json(left, right):
    try:
        with open(left, encoding="utf-8") as handle:
            first = json.load(handle)
        with open(right, encoding="utf-8") as handle:
            second = json.load(handle)
    except (OSError, ValueError):
        return "is not readable as JSON on one side"
    if first == second:
        return ""
    return "declares different images or sizes from what the artwork produces"


def describe_pixels(left, right):
    """Empty where the images are the same picture, whatever the bytes say."""
    from PIL import Image
    with Image.open(left) as first, Image.open(right) as second:
        first = first.convert("RGBA")
        second = second.convert("RGBA")
        if first.size != second.size:
            return f"is {first.size[0]}x{first.size[1]} where the artwork produces " \
                   f"{second.size[0]}x{second.size[1]}"
        left_bytes = first.tobytes()
        right_bytes = second.tobytes()
        if left_bytes == right_bytes:
            return ""
        differing = sum(1 for a, b in zip(left_bytes, right_bytes) if a != b)
        total = len(left_bytes)
        return (f"is a different picture: {differing} of {total} colour channel "
                f"values differ ({differing / total:.1%})")


if __name__ == "__main__":
    sys.exit(main())
