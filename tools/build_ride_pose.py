"""Build the dedicated horse-riding pose for the player rig.

Run headless:
    blender --background --python tools/build_ride_pose.py

The pose is authored in Blender armature space (Z up, character faces -Y)
and exported as Models/ride_pose.glb with a single looping "Ride" action.
tools/build_ride_library.gd then retargets that action onto the player's
%GeneralSkeleton and saves assets/animations/ride.res.

The angles below are the first-pass riding seat.  They are deliberately
explicit so they can be adjusted after looking at the rendered previews in
artifacts/ride_pose_side.png and artifacts/ride_pose_front.png.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Quaternion, Vector

PROJECT = "/home/chrismills029/liv/groom"
SOURCE = os.path.join(PROJECT, "Models", "chris.glb")
TARGET = os.path.join(PROJECT, "Models", "ride_pose.glb")
ARTIFACTS = os.path.join(PROJECT, "artifacts")

# Armature-space target directions.  +X is the character's left, +Z is up,
# -Y is forward.  A bone's local Y axis points from its head to its tail.
TARGETS = {
    # Root / torso: small forward pelvic tilt, upright-but-forward spine.
    "Hips": (0.0, -0.14, -0.99),
    "Spine": (0.0, -0.03, 0.9995),
    "Spine1": (0.0, -0.055, 0.9985),
    "Spine2": (0.0, -0.055, 0.9985),
    "Neck": (0.0, 0.02, 0.9998),
    "Head": (0.0, 0.0, 1.0),
    # Clavicles stay close to horizontal; the arms hang down/forward.
    "LeftShoulder": (1.0, -0.04, 0.0),
    "RightShoulder": (-1.0, -0.04, 0.0),
    "LeftArm": (0.12, -0.10, -0.985),
    "RightArm": (-0.12, -0.10, -0.985),
    "LeftForeArm": (-0.18, -0.88, -0.44),
    "RightForeArm": (0.18, -0.88, -0.44),
    "LeftHand": (-0.12, -0.92, -0.37),
    "RightHand": (0.12, -0.92, -0.37),
    # Thighs forward and out over the barrel; lower legs hang down/back.
    "LeftUpLeg": (0.45, -0.80, -0.40),
    "RightUpLeg": (-0.45, -0.80, -0.40),
    "LeftLeg": (0.02, 0.25, -0.968),
    "RightLeg": (-0.02, 0.25, -0.968),
    "LeftFoot": (0.0, -0.985, 0.17),
    "RightFoot": (0.0, -0.985, 0.17),
    "LeftToeBase": (0.0, -0.98, 0.20),
    "RightToeBase": (0.0, -0.98, 0.20),
}

# Bones that should curl slightly to suggest holding reins.
CURL_BONES = [
    name
    for name in (
        "LeftHandIndex1", "LeftHandIndex2", "LeftHandIndex3",
        "LeftHandMiddle1", "LeftHandMiddle2", "LeftHandMiddle3",
        "LeftHandRing1", "LeftHandRing2", "LeftHandRing3",
        "LeftHandPinky1", "LeftHandPinky2", "LeftHandPinky3",
        "RightHandIndex1", "RightHandIndex2", "RightHandIndex3",
        "RightHandMiddle1", "RightHandMiddle2", "RightHandMiddle3",
        "RightHandRing1", "RightHandRing2", "RightHandRing3",
        "RightHandPinky1", "RightHandPinky2", "RightHandPinky3",
    )
]


def import_rig():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=SOURCE)
    arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
    if arm is None:
        raise RuntimeError("chris.glb contains no armature")
    return arm


def reset_pose(arm):
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.location = (0.0, 0.0, 0.0)
        pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
        pb.scale = (1.0, 1.0, 1.0)
    bpy.context.view_layer.update()


def aim_bone(arm, name, direction):
    """Aim a pose bone's Y axis along an armature-space direction.

    The bone head is taken from the current (already posed) hierarchy, so
    parents must be aimed first.  Rest roll is preserved by rotating the
    bone's armature-space rest basis with the minimal rotation.
    """
    pb = arm.pose.bones[name]
    rest_dir = (pb.bone.tail_local - pb.bone.head_local).normalized()
    target_dir = Vector(direction).normalized()
    rot = rest_dir.rotation_difference(target_dir)
    rest_basis = pb.bone.matrix_local.to_3x3()
    new_basis = rot.to_matrix() @ rest_basis
    pb.matrix = Matrix.Translation(pb.head) @ new_basis.to_4x4()
    bpy.context.view_layer.update()


def apply_pose(arm, sway=0.0):
    reset_pose(arm)

    # Root to fingertips, and root to toes.  Parents must be aimed first.
    order = [
        "Hips",
        "Spine", "Spine1", "Spine2", "Neck", "Head",
        "LeftShoulder", "LeftArm", "LeftForeArm", "LeftHand",
        "RightShoulder", "RightArm", "RightForeArm", "RightHand",
        "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
        "RightUpLeg", "RightLeg", "RightFoot", "RightToeBase",
    ]
    for name in order:
        aim_bone(arm, name, TARGETS[name])

    # Small breathing/sway overlay, applied in each bone's local space.
    if sway:
        for name, angle in (
            ("Spine1", 0.8),
            ("Spine2", 0.5),
            ("Neck", -0.8),
            ("Head", 0.3),
        ):
            pb = arm.pose.bones[name]
            axis = Vector((1.0, 0.0, 0.0))
            pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(axis, math.radians(angle * sway))
        bpy.context.view_layer.update()

    # Curl the fingers to suggest a soft rein grip.  The local X axis points
    # across the hand; a positive rotation folds the fingers toward the palm.
    for name in CURL_BONES:
        pb = arm.pose.bones.get(name)
        if pb is None:
            continue
        axis = Vector((1.0, 0.0, 0.0))
        pb.rotation_quaternion = pb.rotation_quaternion @ Quaternion(axis, math.radians(48.0))
    bpy.context.view_layer.update()


def keyframe_pose(arm, frame, sway):
    apply_pose(arm, sway)
    for pb in arm.pose.bones:
        pb.keyframe_insert("location", frame=frame, group=pb.name)
        pb.keyframe_insert("rotation_quaternion", frame=frame, group=pb.name)
        pb.keyframe_insert("scale", frame=frame, group=pb.name)


def build_action(arm):
    scene = bpy.context.scene
    scene.render.fps = 24
    scene.frame_start = 1
    scene.frame_end = 49
    arm.animation_data_create()
    for frame, sway in ((1, 0.0), (25, 1.0), (49, 0.0)):
        scene.frame_set(frame)
        keyframe_pose(arm, frame, sway)
    action = arm.animation_data.action
    action.name = "Ride"
    action.use_fake_user = True
    scene.frame_set(1)
    return action


def render_previews(arm):
    os.makedirs(ARTIFACTS, exist_ok=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    if scene.world is None:
        scene.world = bpy.data.worlds.new("RidePreviewWorld")
    scene.world.color = (0.05, 0.06, 0.07)

    camera_data = bpy.data.cameras.new("PreviewCamera")
    camera = bpy.data.objects.new("PreviewCamera", camera_data)
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera_data.lens = 55.0

    shots = [
        ("ride_pose_side", (2.9, -0.4, 1.25), (0.0, -0.05, 1.05)),
        ("ride_pose_front", (2.2, -2.8, 1.75), (0.0, -0.08, 1.05)),
        ("ride_pose_back", (-2.2, 2.8, 1.75), (0.0, 0.0, 1.05)),
    ]
    for name, pos, target in shots:
        camera.location = Vector(pos)
        direction = Vector(target) - camera.location
        camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(ARTIFACTS, name + ".png")
        bpy.ops.render.render(write_still=True)
        print("rendered", scene.render.filepath)


def export_glb(arm):
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    # Export the whole character: the importer needs the skeleton, and the
    # library builder only reads the animation tracks.
    bpy.ops.export_scene.gltf(
        filepath=TARGET,
        export_format="GLB",
        use_selection=False,
        export_animations=True,
        export_frame_range=True,
        export_anim_single_armature=True,
        export_force_sampling=True,
        export_optimize_animation_size=False,
        export_nla_strips=False,
        export_apply=False,
    )
    print("exported", TARGET, os.path.getsize(TARGET), "bytes")


def main():
    arm = import_rig()
    action = build_action(arm)
    print("action", action.name, "frames", action.frame_range, "fcurves", len(action.fcurves))
    render_previews(arm)
    export_glb(arm)


if __name__ == "__main__":
    main()
