"""Write the garage wreck's vertex-authored low-poly OBJ parts.

Run with Python 3. The committed OBJs are loaded as-is by Godot; this script is
only an editable source for their triangles, and never runs during play.
"""

from math import cos, pi, sin
from pathlib import Path


OUT = Path(__file__).resolve().parent.parent / "models"


class Mesh:
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
        # OBJ front faces use counter-clockwise winding viewed from outside.
        # The original box quads were inward-facing and disappeared under
        # back-face culling in Godot.
        for quad in ((d, c, b, a), (e, f, g, h), (a, b, f, e),
                     (b, c, g, f), (c, d, h, g), (d, a, e, h)):
            self.face(tuple(reversed(quad)), material)

    def save(self, name):
        lines = ["# Original vertex-authored wreck for Casino Royale", "mtllib car_palette.mtl", "o " + name]
        lines += ["v %.4f %.4f %.4f" % v for v in self.vertices]
        active = None
        for material, face in sorted(self.faces, key=lambda item: item[0]):
            if material != active:
                lines.append("usemtl " + material)
                active = material
            lines.append("f %d %d %d" % face)
        (OUT / (name + ".obj")).write_text("\n".join(lines) + "\n")


def body():
    m = Mesh()
    # Chassis and dark trunk opening. The hinged lid is its own mesh.
    m.box(-2.05, 0.30, -0.82, 2.05, 0.93, 0.82, "paint")
    left = [(-1.20, 0.88, -0.72), (0.94, 0.88, -0.72),
            (0.49, 1.66, -0.63), (-0.72, 1.66, -0.63)]
    right = [(x, y, -z) for x, y, z in left]
    m.face(tuple(reversed(left)), "paint")
    m.face(right, "paint")
    for i in range(4):
        j = (i + 1) % 4
        m.face((left[j], right[j], right[i], left[i]), "paint")
    m.save("wreck_body")


def hood():
    m = Mesh()
    m.box(0.86, 0.85, -0.80, 2.08, 1.025, 0.80, "paint")
    m.save("wreck_hood")


def boot():
    m = Mesh()
    # Local origin is the hinge at the rear of the passenger compartment.
    # The lid rotates upward around the car's z axis when searched.
    m.box(-0.99, 0, -0.78, 0.01, 0.09, 0.78, "paint")
    m.save("wreck_boot")


def cavity():
    m = Mesh()
    m.box(-2.01, 0.935, -0.73, -1.16, 0.965, 0.73, "cavity")
    m.save("wreck_cavity")


def trim():
    m = Mesh()
    # Door seams and side plates make the body read as an old sedan.
    for z in (-0.835, 0.835):
        for x in (-0.94, 0.18, 1.12):
            m.box(x - 0.018, 0.41, z - 0.009, x + 0.018, 0.89, z + 0.009, "seam")
        m.box(-0.64, 0.70, z - 0.025, -0.38, 0.74, z + 0.025, "metal")
        m.box(0.46, 0.70, z - 0.025, 0.72, 0.74, z + 0.025, "metal")
    # Pane polygons sit just outside the painted roof and use dark glass.
    for z in (-0.654, 0.654):
        sign = -1 if z < 0 else 1
        pane = ((-0.69, 1.59, z), (0.44, 1.59, z),
                (0.83, 0.96, sign * 0.748), (-1.11, 0.96, sign * 0.748))
        m.face(pane if z < 0 else tuple(reversed(pane)), "glass")
        m.box(-0.08, 0.97, sign * 0.75 - 0.012,
              -0.035, 1.60, sign * 0.75 + 0.012, "metal")
    m.face(((0.48, 1.59, -0.62), (0.48, 1.59, 0.62),
            (0.91, 0.96, 0.72), (0.91, 0.96, -0.72)), "glass")
    m.face(((-0.73, 1.59, 0.62), (-0.73, 1.59, -0.62),
            (-1.14, 0.96, -0.72), (-1.14, 0.96, 0.72)), "glass")
    for x in (-1.42, 1.42):
        for z in (-0.88, 0.88):
            # Eight-sided tyre and pale inset hubcap, aligned along the z axis.
            for i in range(8):
                a, b = i * 2 * pi / 8, (i + 1) * 2 * pi / 8
                ring = lambda radius, depth, angle: (x + radius * cos(angle),
                                                       0.38 + radius * sin(angle), depth)
                outer_z = z + (0.16 if z > 0 else -0.16)
                inner_z = z - (0.10 if z > 0 else -0.10)
                tyre = (ring(0.36, inner_z, a), ring(0.36, inner_z, b),
                        ring(0.36, outer_z, b), ring(0.36, outer_z, a))
                m.face(tyre if z > 0 else tuple(reversed(tyre)), "rubber")
                cap_z = outer_z + (0.005 if z > 0 else -0.005)
                cap = (ring(0.20, cap_z, a), ring(0.20, cap_z, b),
                       (x, 0.38, cap_z))
                m.face(cap if z > 0 else tuple(reversed(cap)), "metal")
    m.box(-2.18, 0.50, -0.90, -2.05, 0.66, 0.90, "metal")
    m.box(2.05, 0.50, -0.90, 2.18, 0.66, 0.90, "metal")
    for z in (-0.62, 0.62):
        m.box(2.10, 0.67, z - 0.20, 2.14, 0.84, z + 0.20, "lamp")
        m.box(-2.14, 0.67, z - 0.20, -2.10, 0.84, z + 0.20, "tail")
    m.save("wreck_trim")


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    (OUT / "car_palette.mtl").write_text("\n".join(
        "newmtl %s\nKd %.3f %.3f %.3f\nKs 0 0 0\nillum 1\n" % (name, *rgb)
        for name, rgb in {
            "paint": (0.40, 0.40, 0.42), "seam": (0.10, 0.10, 0.10),
            "metal": (0.30, 0.29, 0.25), "glass": (0.065, 0.09, 0.11),
            "rubber": (0.035, 0.035, 0.04), "lamp": (0.64, 0.59, 0.38),
            "tail": (0.47, 0.065, 0.04), "cavity": (0.025, 0.024, 0.022),
        }.items()
    ))
    body()
    hood()
    boot()
    cavity()
    trim()
