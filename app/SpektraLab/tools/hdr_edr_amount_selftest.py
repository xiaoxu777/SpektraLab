#!/usr/bin/env python3
"""hdr_edr_amount_selftest.py -- EDR 强度, how much of the print's EDR is laid on (API-SPEC §26, `edr_amount`).

The owner, 2026-11-25: "EDR 功能应该可以手动调整应用多少吧？最好能加上去". Renders through the engine itself (its
dylib, `engine/tests/spk_ctypes.py`), on a frame whose highlights reach paper white and whose shadows reach the
paper's toe, on a print that carries a measured EDR table:

1. the schema has the field: float, print, not live, default 1, range 0 … 1, after `leak_edge`;
2. EDR on at 1 is EDR on with no field sent, to the bit (every older edit);
3. EDR on at 0 is EDR off, to the bit;
4. EDR off is EDR off whatever the amount (0.5);
5. at 0.25 / 0.5 / 0.75 the picture moves away from EDR off monotonically towards EDR on, every channel of every
   pixel lying between the two (EDR's move is scaled in log2 Y; the encoding after it is monotone);
6. the same on the export's tier (`full`), at 0.5.

    python3 tools/hdr_edr_amount_selftest.py [--library engine/build/libspektralab_engine.dylib] [--resources DIR]

Needs an engine dylib (`engine/build.sh dylib`); exits 2 when there is none (not a pass).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ENGINE = HERE.parents[2] / "engine"
sys.path.insert(0, str(ENGINE / "tests"))
import spk_ctypes as spk  # noqa: E402

BASE = {"film_stock": "kodak_portra_400", "print_stock": "kodak_endura_premier", "grain_active": False,
        "glare_active": False, "auto_exposure": False, "extended_dynamic_range": True}

failures = 0


def check(ok: bool, what: str, detail: str = "") -> None:
    global failures
    print(("PASS " if ok else "FAIL ") + what + (f" -- {detail}" if detail else ""))
    failures += 0 if ok else 1


def frame(w: int = 640, h: int = 420) -> np.ndarray:
    """A ramp from deep shadow to far past white (log-spaced across), a few hues down the side."""
    x = np.linspace(-9.0, 4.0, w)                           # stops around mid-grey
    y = np.linspace(0.0, 1.0, h)[:, None]
    lum = 0.18 * np.exp2(x)[None, :]
    tint = np.stack([1.0 - 0.3 * y, 0.9 + 0.0 * y, 0.7 + 0.3 * y], axis=-1)
    return (lum[..., None] * tint).astype(np.float32)


def render(e: spk.Engine, img: np.ndarray, extra: dict, tier: str = "live") -> np.ndarray:
    p = dict(BASE)
    p.update(extra)
    s = e.open(img, p)
    try:
        rgba, _ = s.render(tier)
    finally:
        s.close()
    return np.asarray(rgba, dtype=np.float64)[..., :3]


def between(mid: np.ndarray, a: np.ndarray, b: np.ndarray, tol: float) -> float:
    lo, hi = np.minimum(a, b) - tol, np.maximum(a, b) + tol
    moved = np.abs(a - b) > tol
    if not moved.any():
        return 1.0
    return float(((mid >= lo) & (mid <= hi))[moved].mean())


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--library", type=Path)
    ap.add_argument("--resources", type=Path, help="engine resources with a metallib (default: the app's "
                    "build/engine-macosx/EngineResources when it is there, else the engine's own)")
    a = ap.parse_args()
    resources = a.resources
    app_res = HERE.parent / "build" / "engine-macosx" / "EngineResources"
    if resources is None and (app_res / "spektralab.metallib").is_file():
        resources = app_res
    try:
        e = spk.Engine(library=a.library, resources=resources)
    except FileNotFoundError as err:
        print(f"SKIP no engine library ({err})")
        return 2

    schema = e.params_schema()
    fields = schema.get("fields", schema)
    by = {f["name"]: f for f in fields} if isinstance(fields, list) else fields
    names = [f["name"] for f in fields] if isinstance(fields, list) else list(fields)
    f = by.get("edr_amount") or {}
    check(f.get("type") == "float" and f.get("layer") == "print" and not f.get("live") and f.get("default") == 1
          and list(f.get("range") or []) == [0, 1],
          "schema: edr_amount is float, print, not live, default 1, range 0..1", str(f))
    if "edr_amount" in names and "leak_edge" in names:
        check(names.index("edr_amount") == names.index("leak_edge") + 1
              and names[names.index("edr_amount") + 1] == "preview_long_edge",
              "schema: after leak_edge, before preview_long_edge")
    if not f:
        print(f"{failures} failure(s)")
        return 1

    img = frame()
    off = render(e, img, {"extended_dynamic_range": False})
    on = render(e, img, {})
    check(not np.array_equal(on, off), "the frame is one EDR moves",
          f"max |on - off| {np.abs(on - off).max():.4f}")
    check(np.array_equal(render(e, img, {"edr_amount": 1.0}), on), "EDR on at 1 = EDR on with no field, to the bit")
    check(np.array_equal(render(e, img, {"edr_amount": 0.0}), off), "EDR on at 0 = EDR off, to the bit")
    check(np.array_equal(render(e, img, {"extended_dynamic_range": False, "edr_amount": 0.5}), off),
          "EDR off at 0.5 = EDR off, to the bit")

    tol = 2e-4
    last = 0.0
    for amount in (0.25, 0.5, 0.75):
        mid = render(e, img, {"edr_amount": amount})
        dist = float(np.abs(mid - off).mean())
        share = between(mid, off, on, tol)
        check(0 < dist and not np.array_equal(mid, on) and share >= 0.999,
              f"EDR at {amount:.2f} lies between off and on",
              f"mean |x - off| {dist:.5f}, between on {share * 100:.2f}% of moved channels")
        check(dist > last, f"EDR at {amount:.2f} is further from off than the amount before", f"{dist:.5f} > {last:.5f}")
        last = dist
    check(float(np.abs(on - off).mean()) > last, "EDR at 1 is furthest of all")

    full_off = render(e, img, {"extended_dynamic_range": False}, "full")
    full_on = render(e, img, {}, "full")
    full_mid = render(e, img, {"edr_amount": 0.5}, "full")
    check(between(full_mid, full_off, full_on, tol) >= 0.999 and not np.array_equal(full_mid, full_on)
          and not np.array_equal(full_mid, full_off), "the export's tier: 0.5 lies between off and on")
    check(np.array_equal(render(e, img, {"edr_amount": 0.0}, "full"), full_off), "the export's tier: 0 = EDR off")

    print(f"{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
