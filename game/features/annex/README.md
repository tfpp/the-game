# Annex routes

Ten rooms connect to the casino through five entrances. The northwest and west
entrances share a loop; the northeast, east and south wings branch off the hub.

Every standalone CSG floor, wall, ceiling and obstacle has collision enabled.
Each corridor combiner has a Walls child ending with passage subtraction volumes
matching the floor footprints. These remove crossing walls at bends and T junctions
while keeping floors and ceilings intact. The round northwest room also has a clearance cut
where its outer wall otherwise protrudes into the adjoining corridor.

Keep subtraction volumes after additive geometry in each combiner. New passages
need continuous floors and standing-player clearance in both directions.
`tests/features/annex/test_accessibility.gd` sweeps the full standing capsule
along all routes and checks floor support every half metre. It includes the hub
so the west petting-parlor exit cannot be fenced off again.
