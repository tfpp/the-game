//! Runtime inspection state and authored poses. Angles are radians, offsets metres.

#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Pose {
    pub offset: [f32; 3],
    pub rotation: [f32; 3],
}

impl Pose {
    fn blend(self, other: Self, t: f32) -> Self {
        let blend = |a: [f32; 3], b: [f32; 3]| std::array::from_fn(|i| a[i] + (b[i] - a[i]) * t);
        Self {
            offset: blend(self.offset, other.offset),
            rotation: blend(self.rotation, other.rotation),
        }
    }
}

#[derive(Clone, Copy)]
struct Profile {
    duration: f32,
    first: Pose,
    second: Pose,
}

impl Profile {
    fn for_weapon(weapon: &str) -> Option<Self> {
        // A compact pistol wrist turn; wider two-sided receiver checks for long guns.
        // Generated ammo families each have a distinct tilt, lift and duration.
        let (duration, lift, back, turn, roll) = match weapon {
            "pistol" => (2.0, 0.10, 0.04, 0.65, -0.70),
            "smg" => (2.35, 0.09, 0.08, 0.50, -0.50),
            "shotgun" => (2.8, 0.07, 0.13, 0.38, -0.42),
            "awp" => (3.1, 0.08, 0.17, 0.32, -0.35),
            "generated:0" => (2.8, 0.07, 0.12, 0.40, -0.42), // buckshot
            "generated:1" => (2.6, 0.09, 0.12, 0.44, -0.48), // rifle
            "generated:2" => (2.15, 0.11, 0.07, 0.58, -0.62), // low caliber
            "generated:3" => (3.2, 0.06, 0.18, 0.30, -0.30), // rocket
            "generated:4" => (3.0, 0.08, 0.15, 0.34, -0.38), // grenade
            "generated:5" => (2.7, 0.12, 0.10, 0.48, -0.58), // plasma
            _ => return None,
        };
        Some(Self {
            duration,
            first: Pose {
                offset: [-0.10, lift, back],
                rotation: [-0.15, turn, roll],
            },
            second: Pose {
                offset: [-0.06, lift * 0.8, back],
                rotation: [0.12, -turn * 0.65, -roll * 0.55],
            },
        })
    }

    fn sample(self, phase: f32) -> Pose {
        let keys = [
            (0.0, Pose::default()),
            (0.22, self.first),
            (0.43, self.first),
            (0.68, self.second),
            (0.80, self.second),
            (1.0, Pose::default()),
        ];
        for pair in keys.windows(2) {
            let [(start, a), (end, b)] = [pair[0], pair[1]];
            if phase <= end {
                let t = ((phase - start) / (end - start)).clamp(0.0, 1.0);
                // Smooth acceleration and deceleration at each held inspection pose.
                let eased = t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
                return a.blend(b, eased);
            }
        }
        Pose::default()
    }
}

#[derive(Default)]
pub struct Inspection {
    profile: Option<Profile>,
    elapsed: f32,
}

impl Inspection {
    pub fn start(&mut self, weapon: &str) -> bool {
        if self.active() {
            return false;
        }
        self.profile = Profile::for_weapon(weapon);
        self.elapsed = 0.0;
        self.active()
    }

    pub fn active(&self) -> bool {
        self.profile.is_some()
    }

    pub fn cancel(&mut self) {
        self.profile = None;
        self.elapsed = 0.0;
    }

    pub fn advance(&mut self, delta: f32) -> Pose {
        let Some(profile) = self.profile else {
            return Pose::default();
        };
        if !delta.is_finite() || delta < 0.0 {
            return profile.sample(self.elapsed / profile.duration);
        }
        self.elapsed += delta;
        if self.elapsed >= profile.duration {
            self.cancel();
            return Pose::default();
        }
        profile.sample(self.elapsed / profile.duration)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const WEAPONS: [&str; 10] = [
        "pistol",
        "smg",
        "shotgun",
        "awp",
        "generated:0",
        "generated:1",
        "generated:2",
        "generated:3",
        "generated:4",
        "generated:5",
    ];

    #[test]
    fn every_gun_moves_and_returns_to_rest_at_any_frame_rate() {
        for weapon in WEAPONS {
            for dt in [1.0 / 30.0, 1.0 / 144.0, 0.37] {
                let mut inspection = Inspection::default();
                assert!(inspection.start(weapon));
                assert_eq!(inspection.advance(0.0), Pose::default());
                let mut moved = false;
                for _ in 0..500 {
                    let pose = inspection.advance(dt);
                    moved |= pose != Pose::default();
                    assert!(
                        pose.offset
                            .into_iter()
                            .chain(pose.rotation)
                            .all(f32::is_finite)
                    );
                }
                assert!(moved, "{weapon}");
                assert!(!inspection.active());
                assert_eq!(inspection.advance(dt), Pose::default());
            }
        }
    }

    #[test]
    fn cancel_repeat_and_non_weapons_are_safe() {
        let mut inspection = Inspection::default();
        assert!(!inspection.start("banana"));
        assert!(inspection.start("awp"));
        let pose = inspection.advance(1.0);
        assert!(!inspection.start("awp"));
        assert_eq!(inspection.advance(0.0), pose);
        assert_eq!(inspection.advance(f32::NAN), pose);
        inspection.cancel();
        assert_eq!(inspection.advance(0.1), Pose::default());
        assert!(inspection.start("pistol"));
    }
}
