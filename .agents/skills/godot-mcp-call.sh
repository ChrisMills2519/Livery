#!/bin/bash
# Godot MCP Helper Script
# Usage: ./godot-mcp-call.sh <tool_name> [arguments_json]
#
# Thin wrapper around godot-mcp-call.mjs, which speaks the protocol properly
# (waits for each response before sending the next message). Do NOT go back to
# piping raw printf lines into npx: the stdio transport can coalesce them into
# one read chunk and die with
#   SyntaxError: Unexpected non-whitespace character after JSON at position ...
#
# Available tools:
#   launch_editor      - Launch Godot editor
#   run_project        - Run the Godot project
#   get_debug_output   - Get current debug output
#   stop_project       - Stop the running project
#   get_godot_version  - Get installed Godot version
#   list_projects      - List Godot projects in directory
#   get_project_info   - Retrieve project metadata
#   create_scene       - Create a new scene file
#   add_node           - Add a node to a scene
#   load_sprite        - Load a sprite into Sprite2D
#   export_mesh_library - Export scene as MeshLibrary
#   save_scene         - Save changes to a scene
#   get_uid            - Get UID for a file
#   update_project_uids - Update UID references

set -e

TOOL_NAME="${1:-}"
# NB: never write this as ARGUMENTS="${2:-{}}" - bash closes the expansion at the
# first '}' and the value comes out as '{}}', which the driver rejects.
ARGUMENTS="$2"
if [ -z "$ARGUMENTS" ]; then
    ARGUMENTS='{}'
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$TOOL_NAME" ]; then
    echo "Usage: $0 <tool_name> [arguments_json]"
    echo ""
    echo "Available tools:"
    echo "  launch_editor      - Launch Godot editor"
    echo "  run_project        - Run the Godot project"
    echo "  get_debug_output   - Get current debug output"
    echo "  stop_project       - Stop the running project"
    echo "  get_godot_version  - Get installed Godot version"
    echo "  list_projects      - List Godot projects in directory"
    echo "  get_project_info   - Retrieve project metadata"
    echo "  create_scene       - Create a new scene file"
    echo "  add_node           - Add a node to a scene"
    echo "  load_sprite        - Load a sprite into Sprite2D"
    echo "  export_mesh_library - Export scene as MeshLibrary"
    echo "  save_scene         - Save changes to a scene"
    echo "  get_uid            - Get UID for a file"
    echo "  update_project_uids - Update UID references"
    exit 1
fi

exec node "$SCRIPT_DIR/godot-mcp-call.mjs" "$TOOL_NAME" "$ARGUMENTS"
