# Codex GLM52 Session and Model Notes

This note documents two Codex CLI behaviors that matter when using the
`glm52` profile:

- why the GLM provider definition must stay inside `glm52.config.toml`
- why `/resume` can show different session lists between `codex` and
  `codex --profile glm52`

## Keep the provider scoped to the profile

The Codex installer must not add this block to the user-level
`~/.codex/config.toml`:

```toml
[model_providers.zai_coding]
name = "Z.ai GLM Coding Plan via local Responses proxy"
base_url = "http://127.0.0.1:11439"
```

Keep it only in `~/.codex/glm52.config.toml`.

If the provider block is present in the global config, Codex can treat the
local GLM proxy as part of the default model-provider catalog. That can narrow
the default `/model` menu to only the proxy's `glm-5.2` result and can produce
warnings such as:

```text
Model metadata for `gpt-5.5` not found. Defaulting to fallback metadata.
```

The installer and the rollback-safe config snippet in this repository keep the
default provider as `openai` and keep `zai_coding` scoped to the `glm52`
profile.

## `/resume` is shared storage, filtered view

Codex stores sessions in the same Codex home regardless of profile. In the
normal setup this means both commands read the same underlying session store:

```bash
codex
codex --profile glm52
```

However, the local TUI `/resume` picker is not a raw dump of every stored
session. It filters the list by:

- current working directory, unless `--all` is used or the picker filter is
  toggled
- interactive source type by default (`cli` and `vscode`)
- current `model_provider`

That last filter is the important profile-specific behavior:

- plain `codex` normally uses `model_provider = "openai"` and shows OpenAI
  sessions
- `codex --profile glm52` uses `model_provider = "zai_coding"` and shows GLM
  sessions

This means the same directory can show different `/resume` results depending
on the active profile. An empty GLM resume list does not necessarily mean the
session store is empty; it often means there are no `zai_coding` sessions for
that directory yet.

## What `--all` does and does not do

`codex resume --all` disables cwd filtering and shows sessions from all
directories.

It does not disable the provider filter. For example:

```bash
codex resume --all
```

shows OpenAI-provider sessions, while:

```bash
codex --profile glm52 resume --all
```

shows GLM-provider sessions across all directories.

## Resume a specific session across providers

If you know the session UUID, direct resume bypasses the picker/list filter:

```bash
codex --profile glm52 resume 019f002d-ff94-7a60-be12-37dec61c7d39
```

This can resume an OpenAI-recorded session while running the GLM profile.
Codex may warn that the recorded model differs from the current model:

```text
This session was recorded with model `gpt-5.5` but is resuming with `glm-5.2`.
Consider switching back to `gpt-5.5` as it may affect Codex performance.
```

That warning is expected. It is a model-continuity warning, not a storage
failure.

## Practical operating rules

- Use plain `codex` for default OpenAI work.
- Use `codex --profile glm52` or `start-codex-glm52` for GLM work.
- Expect `/resume` lists to differ between those two commands.
- Use direct session UUIDs when you intentionally want to resume a session
  across providers.
- Do not add `[model_providers.zai_coding]` to the global
  `~/.codex/config.toml`.
- If the default `/model` menu only shows `glm-5.2`, rerun the installer or
  remove the stale global `[model_providers.zai_coding]` block manually.
