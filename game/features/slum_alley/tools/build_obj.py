"""Build the Rain Alleys' small, editable OBJ meshes from explicit vertices.

Run with Python 3 from any directory. Collision and loot stay in feature.tscn;
these meshes are decoration only, so there is no runtime generation cost.
"""

from pathlib import Path
from math import cos, pi, sin


ROOT = Path(__file__).resolve().parent.parent
PALETTE = {
    "enamel": (0.17, 0.23, 0.22),
    "enamel_edge": (0.29, 0.32, 0.28),
    "rust": (0.34, 0.16, 0.10),
    "iron": (0.10, 0.11, 0.12),
    "glass": (0.055, 0.075, 0.09),
    "frame": (0.24, 0.21, 0.17),
    "board": (0.25, 0.16, 0.095),
    "paper": (0.49, 0.43, 0.30),
    "light": (0.88, 0.64, 0.30),
}


class Obj:
    def __init__(self):
        self.vertices = []
        self.faces = []

    def face(self, points, material):
        first = len(self.vertices) + 1
        self.vertices.extend(points)
        for n in range(1, len(points) - 1):
            self.faces.append((material, (first, first + n, first + n + 1)))

    def box(self, x0, y0, z0, x1, y1, z1, material):
        a, b, c, d = (x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)
        e, f, g, h = (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)
        for quad in ((d, c, b, a), (e, f, g, h), (a, b, f, e),
                     (b, c, g, f), (c, d, h, g), (d, a, e, h)):
            self.face(quad, material)

    def beam(self, start, end, radius, material):
        """Four-sided beam between two points, including angled boards and pipes."""
        dx = end[0] - start[0]
        dy = end[1] - start[1]
        dz = end[2] - start[2]
        length = (dx * dx + dy * dy + dz * dz) ** 0.5
        axis = (dx / length, dy / length, dz / length)
        side = (-axis[2], 0, axis[0])
        side_len = (side[0] ** 2 + side[2] ** 2) ** 0.5
        if side_len < 0.01:
            side = (1, 0, 0)
        else:
            side = tuple(v / side_len for v in side)
        up = (axis[1] * side[2] - axis[2] * side[1],
              axis[2] * side[0] - axis[0] * side[2],
              axis[0] * side[1] - axis[1] * side[0])
        rings = []
        for origin in (start, end):
            rings.append([
                tuple(origin[i] + radius * (side[i] * sx + up[i] * sy)
                      for i in range(3))
                for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))
            ])
        for i in range(4):
            j = (i + 1) % 4
            self.face((rings[0][i], rings[0][j], rings[1][j], rings[1][i]), material)

    def save(self, name):
        mtl = ROOT / "models" / "alley_palette.mtl"
        lines = ["# Original vertex-authored scenery for Casino Royale", "mtllib alley_palette.mtl", "o " + name]
        lines += ["v %.4f %.4f %.4f" % v for v in self.vertices]
        current = None
        # Keep each material contiguous: OBJ importers otherwise create a draw
        # surface for every material switch in the facade/window pattern.
        for material, face in sorted(self.faces, key=lambda item: item[0]):
            if material != current:
                lines.append("usemtl " + material)
                current = material
            lines.append("f %d %d %d" % face)
        (ROOT / "models" / (name + ".obj")).write_text("\n".join(lines) + "\n")
        mtl.write_text("\n".join(
            "newmtl %s\nKd %.3f %.3f %.3f\nKs 0 0 0\nillum 1\n" % (key, *rgb)
            for key, rgb in PALETTE.items()
        ))


def dumpster():
    o = Obj()
    # The collision box sits just inside this shell. An overhanging lid,
    # stamped ribs and exposed wheels break up its otherwise cubic outline.
    o.box(-1.25, -0.82, -0.75, 1.25, 0.66, 0.75, "enamel")
    o.box(-1.31, 0.63, -0.83, 1.31, 0.77, 0.83, "iron")
    o.box(-1.19, 0.77, -0.75, 1.19, 0.84, 0.75, "enamel_edge")
    for x in (-0.86, -0.29, 0.29, 0.86):
        o.box(x - 0.055, -0.7, -0.79, x + 0.055, 0.54, -0.745, "enamel_edge")
        o.box(x - 0.055, -0.7, 0.745, x + 0.055, 0.54, 0.79, "enamel_edge")
    for x in (-0.93, 0.93):
        for z in (-0.55, 0.55):
            o.box(x - 0.2, -1.02, z - 0.12, x + 0.2, -0.70, z + 0.12, "iron")
    o.box(-0.60, 0.85, -0.78, 0.60, 0.90, -0.69, "iron")
    o.box(-0.41, -0.15, -0.81, 0.42, 0.20, -0.79, "paper")
    o.box(-0.95, -0.62, -0.805, -0.32, -0.47, -0.78, "rust")
    o.box(0.39, 0.41, 0.79, 1.06, 0.54, 0.81, "rust")
    o.save("dumpster")


def streets():
    o = Obj()
    # Window banks on both faces of each block, with alternating nailed boards.
    blocks = [(-15, -15, 12), (15, -15, 16), (-15, 15, 14), (15, 15, 10)]
    for block_index, (cx, cz, height) in enumerate(blocks):
        toward_z = 1 if cz < 0 else -1
        toward_x = 1 if cx < 0 else -1
        for floor, y in enumerate((2.4, 5.5, 8.6, 11.7, 14.8)):
            if y + 1.2 >= height:
                continue
            for bay, offset in enumerate((-5, 0, 5)):
                z = cz + toward_z * 8.08
                x = cx + offset
                o.box(x - 0.78, y - 1.0, z - 0.04, x + 0.78, y + 1.0, z + 0.04, "frame")
                o.box(x - 0.67, y - 0.89, z - 0.065, x + 0.67, y + 0.89, z + 0.065, "glass")
                o.box(x - 0.035, y - 0.9, z - 0.085, x + 0.035, y + 0.9, z + 0.085, "frame")
                o.box(x - 0.68, y - 0.04, z - 0.085, x + 0.68, y + 0.04, z + 0.085, "frame")
                if (bay + floor + block_index) % 3 == 0:
                    o.beam((x - 0.7, y - 0.65, z + toward_z * 0.11),
                           (x + 0.7, y + 0.58, z + toward_z * 0.11), 0.075, "board")
                x = cx + toward_x * 8.08
                z = cz + offset
                o.box(x - 0.04, y - 0.9, z - 0.70, x + 0.04, y + 0.9, z + 0.70, "glass")
                o.box(x - 0.07, y - 1.0, z - 0.79, x + 0.07, y + 1.0, z + 0.79, "frame")
                o.box(x - 0.085, y - 0.04, z - 0.79, x + 0.085, y + 0.04, z + 0.79, "frame")
                if (bay + floor + block_index) % 2 == 0:
                    o.beam((x + toward_x * 0.11, y - 0.7, z - 0.70),
                           (x + toward_x * 0.11, y + 0.6, z + 0.70), 0.075, "board")
        # A crooked external fire escape is readable from the central crossing.
        if height >= 12:
            wall_x = cx + toward_x * 8.3
            for floor_y in (3.7, 6.8):
                o.box(wall_x - 0.63, floor_y, cz - 2.5,
                      wall_x + 0.63, floor_y + 0.10, cz + 1.9, "iron")
                for z in (cz - 2.5, cz + 1.9):
                    o.beam((wall_x + toward_x * 0.6, floor_y, z),
                           (wall_x + toward_x * 0.6, floor_y + 0.8, z), 0.035, "iron")
            o.beam((wall_x + toward_x * 0.6, 3.7, cz - 2.2),
                   (wall_x + toward_x * 0.6, 6.8, cz + 1.5), 0.065, "iron")
            o.beam((wall_x + toward_x * 0.6, 3.7, cz + 1.5),
                   (wall_x + toward_x * 0.6, 6.8, cz - 2.2), 0.065, "iron")
    # Grounded poles lead up to the existing flickering lights at y=4.1.
    for x, z in ((5, -16), (-5, 0), (5, 16), (-16, 0), (16, 0)):
        o.box(x - 0.09, 0, z - 0.09, x + 0.09, 4.15, z + 0.09, "iron")
        o.box(x - 0.19, 0, z - 0.19, x + 0.19, 0.28, z + 0.19, "iron")
        o.box(x - 0.44, 3.98, z - 0.15, x + 0.44, 4.17, z + 0.15, "frame")
    # Fine loops sit over the four existing collision fences.
    for side in (-24.5, 24.5):
        for along in range(-23, 24, 2):
            for orientation in (0, 1):
                def p(t):
                    return ((along + sin(t) * 0.35, 3.47 + cos(t) * 0.37, side)
                            if orientation == 0 else
                            (side, 3.47 + cos(t) * 0.37, along + sin(t) * 0.35))
                for k in range(6):
                    o.beam(p(k * 2 * pi / 6), p((k + 1) * 2 * pi / 6), 0.012, "iron")
    o.save("street_details")


if __name__ == "__main__":
    (ROOT / "models").mkdir(exist_ok=True)
    dumpster()
    streets()
