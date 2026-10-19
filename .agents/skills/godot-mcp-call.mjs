#!/usr/bin/env node
// Godot MCP stdio driver.
//
// Usage: node godot-mcp-call.mjs <tool_name> ['{"json":"args"}']
//
// Why this exists: piping `initialize` + `notifications/initialized` +
// `tools/call` into the server from a shell pipeline intermittently fails with
//   SyntaxError: Unexpected non-whitespace character after JSON at position N
// because the MCP stdio transport parses whatever arrives in a single read
// chunk as one JSON document. This driver instead waits for each response
// before writing the next message, and reads the server's stdout line by line.
//
// The server is started with npx exactly like opencode.jsonc does, so
// GODOT_PATH / DEBUG from the environment are honoured.

import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const [toolName, argsJson = "{}"] = process.argv.slice(2);

if (!toolName) {
  console.error("Usage: node godot-mcp-call.mjs <tool_name> ['{\"json\":\"args\"}']");
  console.error("Run with --list to print the available tools.");
  process.exit(1);
}

// --list asks the server itself via tools/list instead of trusting a hardcoded
// list, which is how we notice tools being added upstream.
const listTools = toolName === "--list";

let args = {};
if (!listTools) {
  try {
    args = JSON.parse(argsJson);
  } catch (error) {
    console.error(`Invalid JSON arguments: ${error.message}`);
    process.exit(1);
  }
}

const TIMEOUT_MS = Number(process.env.MCP_TIMEOUT_MS ?? 120000);
// Which MCP package to drive. Override to compare servers, e.g.
//   MCP_PACKAGE=@keeveeg/godot-mcp node godot-mcp-call.mjs --list
// Note the editor-plugin servers (@keeveeg) answer tools/list on their own but
// need the Godot editor open with their addon active for actual tool calls.
const SERVER_PACKAGE = process.env.MCP_PACKAGE ?? "@coding-solo/godot-mcp";

const server = spawn("npx", ["-y", SERVER_PACKAGE], {
  stdio: ["pipe", "pipe", "inherit"],
  env: { ...process.env, GODOT_PATH: process.env.GODOT_PATH ?? "/usr/local/bin/godot" },
});

const pending = new Map();
let exited = false;

const killTimer = setTimeout(() => {
  console.error(`Timed out after ${TIMEOUT_MS}ms waiting for "${toolName}".`);
  shutdown(1);
}, TIMEOUT_MS);

function shutdown(code) {
  if (exited) return;
  exited = true;
  clearTimeout(killTimer);
  server.removeAllListeners("exit");
  server.kill("SIGKILL");
  process.exit(code);
}

createInterface({ input: server.stdout }).on("line", (line) => {
  const text = line.trim();
  // Skip the server's human-readable banner lines ([SERVER] ..., etc).
  if (!text.startsWith("{")) return;
  let message;
  try {
    message = JSON.parse(text);
  } catch {
    return;
  }
  const resolve = message.id !== undefined ? pending.get(message.id) : undefined;
  if (resolve) {
    pending.delete(message.id);
    resolve(message);
  }
});

server.on("exit", (code) => {
  if (!exited && pending.size > 0) {
    console.error(`MCP server exited early (code ${code}).`);
    shutdown(1);
  }
});

function send(message) {
  server.stdin.write(`${JSON.stringify(message)}\n`);
}

function request(id, method, params) {
  return new Promise((resolve) => {
    pending.set(id, resolve);
    send({ jsonrpc: "2.0", id, method, params });
  });
}

const init = await request(1, "initialize", {
  protocolVersion: "2024-11-05",
  capabilities: {},
  clientInfo: { name: "freebuff", version: "1.0" },
});

if (init.error) {
  console.error(`Initialize failed: ${JSON.stringify(init.error)}`);
  shutdown(1);
}

send({ jsonrpc: "2.0", method: "notifications/initialized" });

// Server-side tools/list is answered immediately; tool calls may need to wait for
// a client to attach. The editor-plugin bridge (@keeveeg) accepts the MCP
// handshake while the Godot editor is still closed and then answers
// "Godot editor is not connected". The plugin rescans ports 6505-6514 every
// MCPConfig.RECONNECT_INTERVAL (3s), and the server only exists for as long as
// this process runs -- so hold it open and retry instead of failing on the
// first attempt. Without this, a call always loses the race: the server lives
// ~300ms, the plugin rescans every 3s.
const NOT_CONNECTED_PATTERN = /editor is not connected/i;
const RETRY_INTERVAL_MS = Number(process.env.MCP_RETRY_INTERVAL_MS ?? 1000);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function isNotConnected(msg) {
  if (!msg?.result?.isError) return false;
  const text = (msg.result.content ?? []).map((block) => block.text ?? "").join(" ");
  return NOT_CONNECTED_PATTERN.test(text);
}

let nextId = 2;
let response;

if (listTools) {
  response = await request(nextId++, "tools/list", {});
} else {
  response = await request(nextId++, "tools/call", { name: toolName, arguments: args });
  let attempt = 1;
  while (isNotConnected(response)) {
    await sleep(RETRY_INTERVAL_MS);
    attempt += 1;
    console.error(
      `  (editor not attached - attempt ${attempt}, waiting for the plugin's reconnect sweep)`,
    );
    response = await request(nextId++, "tools/call", { name: toolName, arguments: args });
  }
}

if (response.error) {
  console.error(`"${toolName}" failed: ${JSON.stringify(response.error, null, 2)}`);
  shutdown(1);
}

if (listTools) {
  const tools = response.result?.tools ?? [];
  console.log(`${tools.length} tools`);
  for (const tool of tools) {
    const summary = (tool.description ?? "").split("\n")[0].trim();
    console.log(`- ${tool.name}${summary ? `: ${summary}` : ""}`);
  }
  shutdown(0);
}

const result = response.result ?? {};
console.log(JSON.stringify(result, null, 2));

// MCP text content is buried in the JSON above; print it plainly too.
for (const block of result.content ?? []) {
  if (block.type === "text") console.log(`\n${block.text}`.trimEnd());
}

shutdown(result.isError ? 1 : 0);
