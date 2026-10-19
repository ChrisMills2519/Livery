extends Resource
class_name PlayerModelProfile

## One selectable player body, with the small amount of per-rig data the
## controller needs.  Both current models are retargeted to the same humanoid
## skeleton, so the animation library is shared; the profile only carries the
## scene, facing, scale and saddle/hand fit.

@export var display_name := "Chris"
## Presentation copy used by the character-select screen.
@export var role := "Rider"
@export_multiline var blurb := ""
@export var accent := Color(0.76, 0.86, 0.58, 1.0)
@export var scene: PackedScene
@export var model_yaw_degrees := 180.0
## Facing correction for the character-select turntable.  The retargeted
## bodies do not all come in with the same authored forward axis.
@export var preview_yaw_degrees := 0.0
@export var model_scale := 1.0
@export var hips_to_seat := 0.10
## How far to raise the stirrup treads for this body.  A child's leg cannot
## reach an adult saddle's standard tread height.
@export var stirrup_lift := 0.0
@export var hand_anchor_offset := Vector3.ZERO
@export var ride_pivot := Vector3(0.0, 1.0, 0.0)
@export var ride_camera := Vector3(0.0, 0.0, 4.2)
