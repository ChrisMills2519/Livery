# Godot MCP Connection Skill

## Purpose
Connect to a Godot MCP server to interact with the Godot editor and running game.

## The two servers

| | `@coding-solo/godot-mcp` | `@keeveeg/godot-mcp` |
|---|---|---|
| Tools | 14 | 386 advertised, 385 implemented in the plugin |
| Transport | spawns headless Godot per call | Node server → WebSocket 6505-6514 → Godot **editor** plugin |
| Project changes | none | `teddy-world/addons/godot_mcp/` + `MCPRuntime` autoload + plugin enabled |
| Works without the editor open | yes | **no** ("Godot editor is not connected") |
| Config | none | `teddy-world/godot_mcp_config.json` |

Both are wired into `opencode.jsonc` (`godot` and `godot-keeveeg`). KeeVeeG's
server refuses the MCP handshake unless its cwd contains `project.godot`, so it
is launched through `bash -lc "cd teddy-world && ..."`.

## Driving them from a shell (no MCP client)

```bash
# default: @coding-solo (14 tools), from anywhere
node .agents/skills/godot-mcp-call.mjs <tool_name> ['{"json":"args"}']

# KeeVeeG, must run from the Godot project
cd teddy-world
MCP_PACKAGE=@keeveeg/godot-mcp node ../.agents/skills/godot-mcp-call.mjs <tool_name> '{"json":"args"}'

# ask a server what it exposes (queries tools/list, not a hardcoded list)
node .agents/skills/godot-mcp-call.mjs --list
```

`.agents/skills/godot-mcp-call.sh` is a thin wrapper over the same driver.
`MCP_TIMEOUT_MS` (default 120000) caps a call before the server is killed.

**Why not pipe JSON-RPC with printf:** the MCP stdio transport parses whatever
arrives in a single read chunk as one message, so `initialize` +
`notifications/initialized` + `tools/call` can be coalesced and the server dies
with `SyntaxError: Unexpected non-whitespace character after JSON at position N`.
The driver waits for each response before writing the next message.

## Coding-Solo tools (14)

`launch_editor`, `run_project`, `get_debug_output`, `stop_project`,
`get_godot_version`, `list_projects`, `get_project_info`, `create_scene`,
`add_node`, `load_sprite`, `export_mesh_library`, `save_scene`, `get_uid`,
`update_project_uids`. None of these modify the project, and `run_project`
captures game stdout — handy for printing `Performance` monitors.

## KeeVeeG install (this project)

- Addon: `teddy-world/addons/godot_mcp/` (copied from github.com/KeeVeeG/godot-mcp
  main @ `9ea1a41`; the npm package ships the server only, not the addon).
- Plugin enabled in `teddy-world/project.godot` → `[editor_plugins] enabled`.
- On enable the plugin calls `add_autoload_singleton("MCPRuntime", ...)` and saves
  `project.godot` — you do not add the autoload by hand. (Its README claims the `*`
  prefix means "editor only"; its own code writes `*res://...` and the runtime does
  load in game runs, so ignore that note.)
- **After changing the plugin list, reload the project** (Project → Reload Current
  Project) or restart the editor, otherwise the plugin is never activated and calls
  fail with "Godot editor is not connected".
- Connection state: the plugin scans ports 6505-6514 for a running MCP server and
  shows status in the MCP tab of the bottom panel.
- An exported build includes the `MCPRuntime` autoload and logs
  `[MCP Runtime] Loaded and ready for IPC` — remove the autoload and the plugin entry
  before a release export.

### Tool trimming

`teddy-world/godot_mcp_config.json` lists all 386 tools, enabling 42: read-only
inspection (`get_scene_tree`, `get_node_properties`, `find_nodes_in_group`,
`search_files`, `read_script`, `validate_script`, `get_editor_errors`,
`get_diagnostics`, `get_output_log`, ...), targeted writes (`update_property`,
`batch_get/set_properties`, `open_scene`, `save_scene`, `select_nodes`,
`set_shadow_quality`), run/verify (`play_scene`, `stop_scene`,
`get_editor_screenshot`, `get_game_screenshot`, `take_screenshot_with_context`) and
measure (`get_performance_monitors`, `get_editor_performance`, `get_memory_usage`,
`monitor_properties`, `get_monitor_results`), plus the runtime set
(`get_game_scene_tree`, `get_game_node_properties`, `set_game_node_property`,
`execute_game_script`).

`is_tool_enabled()` defaults to **enabled** for any tool not listed, so the file must
name every tool explicitly. The gate is enforced by the plugin at call time
(`command_router.gd` → `Tool disabled: <name>`); the server does **not** read the
config, so a client that loads the full tool list still sees all 386.

## Troubleshooting

- "Godot editor is not connected" — editor closed, plugin not enabled, or the project
  was not reloaded after enabling the plugin.
- "Not a Godot project directory" — the KeeVeeG server was started outside
  `teddy-world`.
- "Failed to bind to any port in range 6505-6514" — a stale server is running;
  `pkill -f godot-mcp`.
- Headless fallbacks that always work, plugin or not:
  ```bash
  cd teddy-world && godot --headless --quit          # boot the game, read stdout
  cd teddy-world && godot --headless --editor --quit  # load plugins, validate scripts
  godot --version
  ```
