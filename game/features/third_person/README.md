# Third-person camera

F3 toggles the local camera preference. The camera sweeps behind the player's eye
and shortens its distance around collision; the local body is shown when there is
room. Remote players and the player's replicated aim are unaffected.

During WebXR immersion this feature leaves the headset camera and hidden local
body alone. F3 does not change the saved preference in VR, and the same preference
resumes when the session ends. See `tests/features/third_person/` for normal camera
behavior and `tests/features/webxr/test_integration.gd` for the XR transition.
