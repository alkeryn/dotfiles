"""Compare the Lua geometry directly with the user's unmodified bspwm C source.

Optional external reference: BSPWM_SOURCE=/path/to/bspwm (default: ~/tmp/bspwm).
No X server/compositor is used. Build products stay in a temporary directory.
"""
import ctypes
import os
from pathlib import Path
import random
import shutil
import subprocess
import tempfile
import unittest


class Rectangle(ctypes.Structure):
    _fields_ = [("x", ctypes.c_int16), ("y", ctypes.c_int16),
                ("width", ctypes.c_uint16), ("height", ctypes.c_uint16)]


class FocusReferenceTest(unittest.TestCase):
    def test_low_tightness_geometry_matches_bspwm_source(self):
        source = Path(os.environ.get("BSPWM_SOURCE", Path.home() / "tmp/bspwm")) / "src"
        lua = shutil.which("lua")
        compiler = shutil.which("cc")
        if not (source / "geometry.c").is_file() or not lua or not compiler:
            self.skipTest("requires bspwm reference source, cc and lua")
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix="bspwm-focus-reference-") as tmp:
            tmp = Path(tmp)
            shim = tmp / "settings.c"
            shim.write_text('#include "types.h"\n'
                            'tightness_t directional_focus_tightness = TIGHTNESS_LOW;\n')
            library = tmp / "geometry.so"
            subprocess.run([compiler, "-shared", "-fPIC", "-I", str(source),
                            str(source / "geometry.c"), str(shim), "-o", str(library)],
                           check=True, capture_output=True, text=True)
            reference = ctypes.CDLL(str(library))
            reference.on_dir_side.argtypes = [Rectangle, Rectangle, ctypes.c_int]
            reference.on_dir_side.restype = ctypes.c_bool
            reference.boundary_distance.argtypes = [Rectangle, Rectangle, ctypes.c_int]
            reference.boundary_distance.restype = ctypes.c_uint32

            # Keep endpoints inside int16, as bspwm's xcb_point_t uses int16.
            # Include coincident, contained, one-pixel, touching and disjoint
            # rectangles as well as random sizes and negative coordinates.
            boxes = [(x, y, w, h) for x in (-100, -1, 0, 1, 100)
                     for y in (-100, -1, 0, 1, 100)
                     for w, h in ((1, 1), (1, 100), (100, 1), (100, 100), (200, 200))]
            pairs = [(a, b) for a in boxes for b in boxes]
            rng = random.Random(90751)
            for _ in range(5000):
                pairs.append(tuple((rng.randint(-2000, 2000), rng.randint(-2000, 2000),
                                    rng.randint(1, 2000), rng.randint(1, 2000)) for _ in range(2)))
            cases, expected = [], []
            for a, b in pairs:
                for direction, key in enumerate(("u", "l", "d", "r")):
                    cases.append(" ".join(map(str, (*a, *b, key))))
                    value = -1
                    if reference.on_dir_side(Rectangle(*a), Rectangle(*b), direction):
                        value = reference.boundary_distance(Rectangle(*a), Rectangle(*b), direction)
                    expected.append(str(value))
            runner = tmp / "compare.lua"
            runner.write_text('''local focus = require("lua/extensions/bspwm_focus")
for line in io.lines() do
    local fields = {}
    for value in line:gmatch("%S+") do fields[#fields + 1] = tonumber(value) or value end
    local a = { x=fields[1], y=fields[2], w=fields[3], h=fields[4] }
    local b = { x=fields[5], y=fields[6], w=fields[7], h=fields[8] }
    print(focus.distance(a, b, fields[9]) or -1)
end
''')
            for interpreter in dict.fromkeys(filter(None, (lua, shutil.which("luajit")))):
                result = subprocess.run([interpreter, str(runner)], cwd=root,
                                        input="\n".join(cases) + "\n", capture_output=True,
                                        text=True, check=True)
                actual = result.stdout.splitlines()
                self.assertEqual(len(actual), len(expected))
                for case, want, got in zip(cases, expected, actual):
                    self.assertEqual(got, want, f"{interpreter}: {case}")


if __name__ == "__main__":
    unittest.main()
