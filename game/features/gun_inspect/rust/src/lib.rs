mod motion;

use godot::prelude::*;
use motion::Inspection;

struct GunInspectExtension;

#[gdextension]
unsafe impl ExtensionLibrary for GunInspectExtension {}

/// Runtime animation controller; GDScript only connects input and the weapon mounts.
#[derive(GodotClass)]
#[class(base=RefCounted)]
struct WeaponInspect {
    motion: Inspection,
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for WeaponInspect {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            motion: Inspection::default(),
            base,
        }
    }
}

#[godot_api]
impl WeaponInspect {
    #[func]
    fn start(&mut self, weapon: GString) -> bool {
        self.motion.start(&weapon.to_string())
    }

    #[func]
    fn is_active(&self) -> bool {
        self.motion.active()
    }

    #[func]
    fn cancel(&mut self) {
        self.motion.cancel();
    }

    #[func]
    fn advance(&mut self, delta: f64) -> Transform3D {
        let pose = self.motion.advance(delta as f32);
        let vector = |v: [f32; 3]| Vector3::new(v[0], v[1], v[2]);
        Transform3D::new(
            Basis::from_euler(EulerOrder::YXZ, vector(pose.rotation)),
            vector(pose.offset),
        )
    }
}
