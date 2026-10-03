# CPU frog detail source

The existing frog detail sphere has a 0.5 m radius, 1 m height, 12 radial
segments and six rings. `bake_cpu_sphere.gd` preserves its vertices, normals and
indices in `game/assets/frogs/models/sphere_source.tres`. Rebuild with:

```sh
godot --headless --path game -s ../docs/design/model-sources/frogs/bake_cpu_sphere.gd
```

Batched detail construction reads this CPU resource instead of calling
`SphereMesh.surface_get_arrays()` three times per frog. The visible torso still
uses the same primitive. This removes runtime GPU readbacks without changing the
model or adding a runtime mesh surface. A parity test compares the baked data to
the original Godot primitive.
