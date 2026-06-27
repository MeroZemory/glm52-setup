# Claude Code → GLM-5.2 (Roadmap / Placeholder)

## Status: 🔬 Research / Not yet implemented

This directory is reserved for Claude Code integration with Z.ai GLM-5.2.

## Technical Difference

| | Codex | Claude Code |
|---|---|---|
| **API format** | OpenAI Responses API | Anthropic Messages API |
| **Proxy converts** | Responses → Chat Completions | Messages → Chat Completions *(needs writing)* |
| **MCP support** | Native (config.toml) | Via `.mcp.json` / CLI flags |

## Planned Approach

1. Write `proxy/zai-claude-messages-proxy.mjs`:
   - Accept Anthropic Messages API (`/v1/messages`)
   - Convert `messages[]` → Z.ai Chat Completions format
   - Convert tool_use / tool_result blocks ↔ function calls
   - Map Claude `thinking` → GLM `thinking`

2. Claude Code config:
   ```json
   {
     "env": {
       "ANTHROPIC_BASE_URL": "http://127.0.0.1:11440"
     }
   }
   ```

3. Scripts: `claude/scripts/start-claude-glm52.sh`

## Open Questions

- Does Z.ai expose an Anthropic-compatible endpoint? If yes, no proxy needed.
- Claude Code's tool-use streaming format differs significantly from OpenAI's.
- MCP server config format differs between Codex and Claude Code.

Contributions welcome!
