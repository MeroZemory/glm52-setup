# glm52-setup

> Use **Z.ai GLM-5.2** inside **OpenAI Codex** — with full MCP, plugin, and feature inheritance from your existing GPT-5.5 setup. Zero disruption to your default model.

```
┌─────────────┐      Responses API       ┌──────────────┐     Chat Completions     ┌─────────────┐
│   Codex     │  ────────────────────▶   │  Local Proxy │  ─────────────────────▶  │  Z.ai GLM   │
│  --profile  │  ◀────────────────────   │  (port 11439)│  ◀─────────────────────  │   API       │
│   glm52     │   SSE stream back        └──────────────┘   SSE stream back        └─────────────┘
└─────────────┘
```

---

## 🧠 For AI Agents: One-Prompt Setup

> **Paste this to your coding agent (Codex, Claude, Cursor, etc.) to set everything up automatically:**

```text
Clone https://github.com/MeroZemory/glm52-setup and run the installer for my OS
(powershell -ExecutionPolicy Bypass -File install.ps1 on Windows,
 bash install.sh on Linux/macOS).

The installer copies the proxy, profile, and scripts into ~/.codex/,
backs up my existing config.toml, and patches it with the
[model_providers.zai_coding] block.

After install, verify the setup works by running start-codex-glm52
and sending a simple test prompt. If verification fails after 3 attempts,
run rollback.ps1 (Windows) or rollback.sh (Linux/macOS) to fully revert,
then tell me what went wrong.
```

The agent will: **clone → install → verify → (rollback if broken)** — hands-free.

---

## ⚠️ If Your Agent Goes Silent / Unresponsive

> **Run this one command to fully undo everything:**

| OS | Rollback command |
|---|---|
| **Windows** | `powershell -ExecutionPolicy Bypass -File rollback.ps1` |
| **Linux/macOS** | `bash rollback.sh` |

This kills the proxy, removes all installed files, and restores your original `config.toml` from backup. **No manual cleanup needed. Your GPT-5.5 default is 100% unaffected.**

> ℹ️ The rollback scripts are **deterministic** — they don't depend on the agent. You can run them yourself in a terminal even if Codex is completely frozen or you've hit a usage limit. They're committed to the repo at `rollback.ps1` / `rollback.sh`.

---

## Quick Start (Manual)

### Prerequisites

- [OpenAI Codex CLI](https://developers.openai.com/codex) installed and authenticated
- [Node.js](https://nodejs.org) 18+
- Z.ai API key — get one at [https://z.ai](https://z.ai)

### Install

**Windows (tested ✅):**
```powershell
git clone https://github.com/MeroZemory/glm52-setup.git
cd glm52-setup
powershell -ExecutionPolicy Bypass -File install.ps1
```

**Linux / macOS (untested ⚠️):**
```bash
git clone https://github.com/MeroZemory/glm52-setup.git
cd glm52-setup
bash install.sh
```

> ⚠️ **The Linux/macOS scripts (`.sh`) are untested.** They were written to mirror the Windows logic but have not been verified on any Linux distro or macOS version. If you're on Linux/macOS, please review the scripts before running and report any issues.

The installer will:
1. ✅ Check Node.js + Codex CLI
2. ✅ **Back up** your existing `config.toml` → `config.toml.pre-glm52.bak`
3. ✅ Copy the proxy, profile, and scripts to `~/.codex/`
4. ✅ **Patch** `config.toml` with the `[model_providers.zai_coding]` block
5. ✅ Prompt for your `ZAI_API_KEY` and save it

### Run

```bash
# Option A: one-shot (starts proxy + codex)
start-codex-glm52        # Windows: .cmd | Unix: .sh

# Option B: manual
start-proxy              # start the proxy
codex --profile glm52    # launch codex with GLM-5.2
```

### Switch back to GPT-5.5

Just use `codex` normally — no flags needed. Your default model is untouched.

### Uninstall / Roll Back

```bash
# Windows
powershell -ExecutionPolicy Bypass -File rollback.ps1

# Linux/macOS
bash rollback.sh
```

Removes everything, restores your original config. Safe to run multiple times.

---

## How It Works

1. **Profile override** (`glm52.config.toml`) sets `model = "glm-5.2"` and `model_provider = "zai_coding"` while inheriting everything else from your main `config.toml`
2. **Local proxy** (`zai-codex-responses-proxy.mjs`) translates Codex's OpenAI Responses API calls into Z.ai's Chat Completions API — including tool calls, streaming, and reasoning
3. **Launch scripts** start the proxy in the background, then launch Codex with the profile

## Why?

- **Keep GPT-5.5 as default** — GLM-5.2 runs as a *profile*, not a replacement
- **Full MCP inheritance** — all your MCP servers, plugins, skills work unchanged
- **Cost-effective** — route heavy reasoning tasks to GLM when GPT quota runs out
- **One command** — `start-codex-glm52` starts the proxy + launches Codex

---

## What Gets Inherited?

When you run `codex --profile glm52`, **everything except the model is inherited** from your main `config.toml`:

| Setting | Source | Inherited? |
|---------|--------|:----------:|
| `model` | glm52 profile | ❌ overridden → `glm-5.2` |
| `model_provider` | glm52 profile | ❌ overridden → `zai_coding` |
| MCP servers | main config | ✅ |
| Plugins | main config | ✅ |
| Features (multi_agent, js_repl, etc.) | main config | ✅ |
| Trusted projects | main config | ✅ |
| Sandbox / approval policy | main config | ✅ |
| Reasoning effort / verbosity | glm52 profile | ❌ overridden |

This means **your MCP servers (Playwright, Jira, IDA, etc.), plugins (GitHub, Figma, Browser), and all features work identically** with GLM-5.2.

---

## Repository Structure

```
glm52-setup/
├── proxy/
│   └── zai-codex-responses-proxy.mjs   # Responses→Chat translation proxy
├── codex/
│   ├── profiles/
│   │   └── glm52.config.toml            # Model override profile
│   └── scripts/
│       ├── start-proxy.{cmd,sh}         # Launch proxy in background
│       ├── stop-proxy.{cmd,sh}          # Kill proxy
│       └── start-codex-glm52.{cmd,sh}   # Proxy + codex launcher
├── install.ps1                          # Windows installer (tested)
├── install.sh                           # Linux/macOS installer (untested)
├── rollback.ps1                         # Windows rollback (tested)
├── rollback.sh                          # Linux/macOS rollback (untested)
└── README.md
```

---

## Configuration Details

### Environment Variables

| Variable | Required | Description |
|----------|:--------:|-------------|
| `ZAI_API_KEY` | ✅ | Z.ai API key (or `Z_AI_API_KEY` / `ZHIPUAI_API_KEY`) |
| `ZAI_CHAT_URL` | ❌ | Override upstream URL (default: `https://api.z.ai/api/coding/paas/v4/chat/completions`) |
| `ZAI_MODEL` | ❌ | Override model slug (default: `glm-5.2`) |
| `ZAI_CODEX_PROXY_HOST` | ❌ | Proxy bind host (default: `127.0.0.1`) |
| `ZAI_CODEX_PROXY_PORT` | ❌ | Proxy bind port (default: `11439`) |

### What Gets Added to Your config.toml

The installer automatically appends this block (and backs up the original first):

```toml
[model_providers.zai_coding]
name = "Z.ai GLM Coding Plan via local Responses proxy"
base_url = "http://127.0.0.1:11439"
```

The profile handles the rest.

### Reasoning Effort Mapping

| Codex effort | GLM reasoning |
|-------------|---------------|
| `low` | `high` |
| `medium` | `high` |
| `high` | `high` |
| `xhigh` / `max` | `max` |

---

## How the Proxy Works

The proxy (`zai-codex-responses-proxy.mjs`) runs on `127.0.0.1:11439` and:

1. **Accepts** Codex's Responses API calls (`POST /responses`)
2. **Converts** the Responses input array → Chat Completions messages array:
   - `instructions` → system message
   - Items with `role` → mapped to chat roles
   - `function_call` items → assistant message with `tool_calls`
   - `function_call_output` → tool role message
3. **Converts** namespace tools (`type: "namespace"`) → flat function tools (`mcp__server__tool`)
4. **Forwards** to Z.ai with streaming enabled + `thinking: { type: "enabled" }`
5. **Streams back** SSE events translated to Codex's Responses format

All conversion happens transparently — Codex thinks it's talking to OpenAI.

---

## Troubleshooting

<details>
<summary><b>Port 11439 already in use</b></summary>

```bash
stop-proxy          # kill existing
start-proxy         # restart
```
</details>

<details>
<summary><b>401 Unauthorized</b></summary>

Set your API key:
```powershell
# Windows
[Environment]::SetEnvironmentVariable("ZAI_API_KEY","your-key","User")
```
```bash
# Linux/macOS
echo 'export ZAI_API_KEY="your-key"' >> ~/.bashrc
```
</details>

<details>
<summary><b>Proxy not starting / connection refused</b></summary>

Check the logs:
```bash
cat ~/.codex/zai-codex-proxy.err.log
```
Ensure Node.js is in PATH: `node -v`
</details>

<details>
<summary><b>GLM-5.2 is slow / reasoning too long</b></summary>

Lower the reasoning effort in `glm52.config.toml`:
```toml
model_reasoning_effort = "high"   # or "medium", "low"
```
</details>

<details>
<summary><b>Config.toml got messed up</b></summary>

Run rollback, then re-install:
```bash
rollback.ps1     # or rollback.sh
install.ps1      # or install.sh
```

The rollback restores your original `config.toml` from the backup made during install.
</details>

---

## Requirements

- OpenAI Codex CLI
- Node.js 18+
- Z.ai API key ([get one](https://z.ai))

## License

MIT
