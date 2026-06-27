import { createServer } from 'node:http';
import { spawnSync } from 'node:child_process';

const HOST = process.env.ZAI_CODEX_PROXY_HOST || '127.0.0.1';
const PORT = Number(process.env.ZAI_CODEX_PROXY_PORT || '11439');
const ZAI_CHAT_URL = process.env.ZAI_CHAT_URL || 'https://api.z.ai/api/coding/paas/v4/chat/completions';
const DEFAULT_MODEL = process.env.ZAI_MODEL || 'glm-5.2';

function readUserEnv(name) {
  if (process.env[name]) return process.env[name];
  if (process.platform !== 'win32') return '';
  const ps = spawnSync(
    'powershell.exe',
    ['-NoProfile', '-Command', `[Environment]::GetEnvironmentVariable('${name}', 'User')`],
    { encoding: 'utf8' },
  );
  return ps.status === 0 ? ps.stdout.trim() : '';
}

function getApiKey(req) {
  const envKey = readUserEnv('ZAI_API_KEY') || readUserEnv('Z_AI_API_KEY') || readUserEnv('ZHIPUAI_API_KEY');
  if (envKey) return envKey;
  const auth = req.headers.authorization;
  if (typeof auth === 'string' && auth.toLowerCase().startsWith('bearer ')) {
    const token = auth.slice('bearer '.length).trim();
    if (token.length > 0) return token;
  }
  return '';
}

function readJson(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      try {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve(text.length === 0 ? {} : JSON.parse(text));
      } catch (err) {
        reject(err);
      }
    });
    req.on('error', reject);
  });
}

function contentToText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map((part) => {
      if (typeof part === 'string') return part;
      if (part && typeof part === 'object') {
        if (typeof part.text === 'string') return part.text;
        if (typeof part.input_text === 'string') return part.input_text;
        if (typeof part.output_text === 'string') return part.output_text;
      }
      return '';
    })
    .filter(Boolean)
    .join('\n');
}

function responseInputToMessages(body) {
  const messages = [];
  if (typeof body.instructions === 'string' && body.instructions.trim().length > 0) {
    messages.push({ role: 'system', content: body.instructions });
  }
  const input = body.input;
  if (typeof input === 'string') {
    messages.push({ role: 'user', content: input });
    return messages;
  }
  if (!Array.isArray(input)) return messages;

  let pendingAssistantToolCalls = [];
  const flushAssistantToolCalls = () => {
    if (pendingAssistantToolCalls.length === 0) return;
    messages.push({ role: 'assistant', content: '', tool_calls: pendingAssistantToolCalls });
    pendingAssistantToolCalls = [];
  };

  for (const item of input) {
    if (!item || typeof item !== 'object') continue;
    if (item.type === 'function_call') {
      const namespace = typeof item.namespace === 'string' ? item.namespace : '';
      pendingAssistantToolCalls.push({
        id: item.call_id || item.id || `call_${pendingAssistantToolCalls.length}`,
        type: 'function',
        function: {
          name: namespace ? `${namespace}__${item.name || 'tool'}` : item.name || 'tool',
          arguments: typeof item.arguments === 'string' ? item.arguments : JSON.stringify(item.arguments ?? {}),
        },
      });
      continue;
    }
    if (item.type === 'function_call_output') {
      flushAssistantToolCalls();
      messages.push({
        role: 'tool',
        tool_call_id: item.call_id || item.id || 'call_0',
        content: typeof item.output === 'string' ? item.output : JSON.stringify(item.output ?? ''),
      });
      continue;
    }
    if (typeof item.role === 'string') {
      flushAssistantToolCalls();
      const role = item.role === 'developer' ? 'system' : item.role;
      messages.push({ role, content: contentToText(item.content) });
    }
  }
  flushAssistantToolCalls();
  return messages;
}

function splitToolName(flatName, namespaces) {
  if (!namespaces || namespaces.length === 0) return { name: flatName };
  for (const ns of [...namespaces].sort((a, b) => b.length - a.length)) {
    const prefix = ns + '__';
    if (flatName.startsWith(prefix)) {
      return { name: flatName.slice(prefix.length), namespace: ns };
    }
  }
  return { name: flatName };
}

function responseToolsToChatTools(tools) {
  if (!Array.isArray(tools)) return { tools: undefined, namespaces: [] };
  const converted = [];
  const namespaces = [];
  for (const tool of tools) {
    if (!tool || typeof tool !== 'object') continue;
    // Expand namespace tools (type: "namespace") into individual Chat Completions
    // function tools with flat names like "mcp__playwright__browser_navigate".
    if (tool.type === 'namespace' && Array.isArray(tool.tools)) {
      const ns = tool.name;
      if (typeof ns !== 'string' || ns.length === 0) continue;
      namespaces.push(ns);
      for (const fn of tool.tools) {
        if (!fn || typeof fn !== 'object') continue;
        const fnName = fn.name;
        if (typeof fnName !== 'string' || fnName.length === 0) continue;
        converted.push({
          type: 'function',
          function: {
            name: ns + '__' + fnName,
            description: fn.description || '',
            parameters: fn.parameters || fn.input_schema || { type: 'object', properties: {} },
          },
        });
      }
      continue;
    }
    const name = tool.name || tool.function?.name;
    if (typeof name !== 'string' || name.length === 0) continue;
    if (tool.type !== 'function') continue;
    const parameters =
      tool.parameters ||
      tool.function?.parameters ||
      tool.input_schema ||
      tool.inputSchema ||
      { type: 'object', properties: {} };
    converted.push({
      type: 'function',
      function: {
        name,
        description: tool.description || tool.function?.description || '',
        parameters,
      },
    });
  }
  return { tools: converted.length > 0 ? converted : undefined, namespaces };
}

function effortFor(body) {
  const effort = body.reasoning?.effort || body.reasoning_effort || '';
  if (['xhigh', 'max', 'ultracode'].includes(String(effort).toLowerCase())) return 'max';
  if (['low', 'medium', 'high'].includes(String(effort).toLowerCase())) return 'high';
  return 'max';
}

function chatPayload(body) {
  const { tools, namespaces } = responseToolsToChatTools(body.tools);
  const payload = {
    model: body.model || DEFAULT_MODEL,
    messages: responseInputToMessages(body),
    stream: body.stream !== false,
    thinking: { type: 'enabled' },
    reasoning_effort: effortFor(body),
    max_tokens: body.max_output_tokens || body.max_tokens || 16384,
  };
  if (typeof body.temperature === 'number') payload.temperature = body.temperature;
  if (tools) {
    payload.tools = tools;
    payload.parallel_tool_calls = body.parallel_tool_calls !== false;
  }
  return { payload, namespaces };
}

function sse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify({ type: event, ...data })}\n\n`);
}

function responseMessage(text, model, usage = undefined) {
  const now = Math.floor(Date.now() / 1000);
  return {
    id: `resp_${now}`,
    object: 'response',
    created_at: now,
    model,
    status: 'completed',
    output: [
      {
        id: `msg_${now}`,
        type: 'message',
        status: 'completed',
        role: 'assistant',
        content: [{ type: 'output_text', text, annotations: [] }],
      },
    ],
    usage,
  };
}

function sendNonStreamResponse(res, chat, model, namespaces) {
  const message = chat.choices?.[0]?.message || {};
  const text = typeof message.content === 'string' ? message.content : '';
  const output = [];
  if (text.length > 0) {
    output.push({
      id: `msg_${Date.now()}`,
      type: 'message',
      status: 'completed',
      role: 'assistant',
      content: [{ type: 'output_text', text, annotations: [] }],
    });
  }
  for (const toolCall of message.tool_calls || []) {
    const split = splitToolName(toolCall.function?.name || 'tool', namespaces);
    output.push({
      id: toolCall.id || `fc_${Date.now()}`,
      type: 'function_call',
      status: 'completed',
      call_id: toolCall.id || `call_${Date.now()}`,
      name: split.name,
      ...(split.namespace ? { namespace: split.namespace } : {}),
      arguments: toolCall.function?.arguments || '{}',
    });
  }
  const body = responseMessage(text, model, chat.usage);
  if (output.length > 0) body.output = output;
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

async function proxyStream(res, upstream, model, namespaces) {
  res.writeHead(200, {
    'content-type': 'text/event-stream',
    'cache-control': 'no-cache',
    connection: 'keep-alive',
  });

  const responseId = `resp_${Date.now()}`;
  const messageId = `msg_${Date.now()}`;
  const textParts = [];
  const toolCalls = new Map();
  let outputIndex = 0;
  let messageStarted = false;
  let textPartStarted = false;

  sse(res, 'response.created', {
    response: { id: responseId, object: 'response', created_at: Math.floor(Date.now() / 1000), model, status: 'in_progress', output: [] },
  });

  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of upstream.body) {
    buffer += decoder.decode(chunk, { stream: true });
    let sep;
    while ((sep = buffer.indexOf('\n\n')) !== -1) {
      const block = buffer.slice(0, sep);
      buffer = buffer.slice(sep + 2);
      for (const line of block.split(/\r?\n/)) {
        if (!line.startsWith('data:')) continue;
        const data = line.slice('data:'.length).trim();
        if (data === '[DONE]') continue;
        let parsed;
        try {
          parsed = JSON.parse(data);
        } catch {
          continue;
        }
        const choice = parsed.choices?.[0];
        const delta = choice?.delta || {};
        if (typeof delta.content === 'string' && delta.content.length > 0) {
          if (!messageStarted) {
            messageStarted = true;
            sse(res, 'response.output_item.added', {
              output_index: outputIndex,
              item: { id: messageId, type: 'message', status: 'in_progress', role: 'assistant', content: [] },
            });
          }
          if (!textPartStarted) {
            textPartStarted = true;
            sse(res, 'response.content_part.added', {
              item_id: messageId,
              output_index: outputIndex,
              content_index: 0,
              part: { type: 'output_text', text: '', annotations: [] },
            });
          }
          textParts.push(delta.content);
          sse(res, 'response.output_text.delta', {
            item_id: messageId,
            output_index: outputIndex,
            content_index: 0,
            delta: delta.content,
          });
        }
        for (const tc of delta.tool_calls || []) {
          const index = tc.index ?? 0;
          const existing = toolCalls.get(index) || {
            id: tc.id || `call_${index}_${Date.now()}`,
            name: tc.function?.name || '',
            arguments: '',
            outputIndex: messageStarted ? outputIndex + 1 + index : outputIndex + index,
            started: false,
          };
          if (tc.id) existing.id = tc.id;
          if (tc.function?.name) existing.name = tc.function.name;
          if (tc.function?.arguments) existing.arguments += tc.function.arguments;
          if (!existing.started) {
            existing.started = true;
            sse(res, 'response.output_item.added', {
              output_index: existing.outputIndex,
              item: {
                id: existing.id,
                type: 'function_call',
                status: 'in_progress',
                call_id: existing.id,
                name: existing.name || 'tool',
                arguments: '',
              },
            });
          }
          if (tc.function?.arguments) {
            sse(res, 'response.function_call_arguments.delta', {
              item_id: existing.id,
              output_index: existing.outputIndex,
              delta: tc.function.arguments,
            });
          }
          toolCalls.set(index, existing);
        }
      }
    }
  }

  const output = [];
  const text = textParts.join('');
  if (messageStarted) {
    sse(res, 'response.output_text.done', { item_id: messageId, output_index: outputIndex, content_index: 0, text });
    sse(res, 'response.content_part.done', {
      item_id: messageId,
      output_index: outputIndex,
      content_index: 0,
      part: { type: 'output_text', text, annotations: [] },
    });
    const messageItem = {
      id: messageId,
      type: 'message',
      status: 'completed',
      role: 'assistant',
      content: [{ type: 'output_text', text, annotations: [] }],
    };
    sse(res, 'response.output_item.done', { output_index: outputIndex, item: messageItem });
    output.push(messageItem);
    outputIndex += 1;
  }
  for (const tc of [...toolCalls.values()].sort((a, b) => a.outputIndex - b.outputIndex)) {
    const split = splitToolName(tc.name || 'tool', namespaces);
    const item = {
      id: tc.id,
      type: 'function_call',
      status: 'completed',
      call_id: tc.id,
      name: split.name,
      ...(split.namespace ? { namespace: split.namespace } : {}),
      arguments: tc.arguments || '{}',
    };
    sse(res, 'response.function_call_arguments.done', {
      item_id: tc.id,
      output_index: tc.outputIndex,
      arguments: item.arguments,
    });
    sse(res, 'response.output_item.done', { output_index: tc.outputIndex, item });
    output.push(item);
  }
  sse(res, 'response.completed', {
    response: { id: responseId, object: 'response', created_at: Math.floor(Date.now() / 1000), model, status: 'completed', output },
  });
  res.end();
}

function sendError(res, status, message) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: { message } }));
}

function modelCatalogEntry(slug, displayName, priority) {
  return {
    id: slug,
    slug,
    name: displayName,
    display_name: displayName,
    description: 'Z.ai GLM 5.2 through a local Responses-to-Chat-Completions proxy.',
    provider: 'z.ai',
    default_reasoning_level: 'high',
    supported_reasoning_levels: [
      { effort: 'low', description: 'Fast responses with lighter reasoning' },
      { effort: 'medium', description: 'Balanced speed and reasoning' },
      { effort: 'high', description: 'Greater reasoning depth' },
      { effort: 'xhigh', description: 'Maximum reasoning depth mapped to Z.ai max thinking' },
    ],
    shell_type: 'shell_command',
    visibility: 'list',
    supported_in_api: true,
    priority,
    context_window: 1000000,
    effective_context_window_percent: 95,
    max_output_tokens: 16384,
    supports_reasoning: true,
    supports_reasoning_summaries: true,
    supports_vision: false,
    supports_parallel_tool_calls: true,
    support_verbosity: true,
    default_verbosity: 'low',
    base_instructions: '',
    model_messages: {
      instructions_template: '{{ personality }}',
      instructions_variables: {
        personality_default: '',
        personality_pragmatic: '',
        personality_friendly: '',
      },
    },
    default_reasoning_summary: 'none',
    apply_patch_tool_type: 'freeform',
    web_search_tool_type: 'text_and_image',
    truncation_policy: { mode: 'tokens', limit: 10000 },
    supports_image_detail_original: false,
    max_context_window: 1000000,
    experimental_supported_tools: [],
    input_modalities: ['text'],
    supports_search_tool: false,
    use_responses_lite: false,
    additional_speed_tiers: [],
    service_tiers: [],
    availability_nux: null,
    upgrade: null,
  };
}

const server = createServer(async (req, res) => {
  try {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
      return;
    }
    if (req.method === 'GET' && (req.url || '').startsWith('/models')) {
      const models = [modelCatalogEntry(DEFAULT_MODEL, 'GLM 5.2', 0)];
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({
        models,
        object: 'list',
        data: models.map((model) => ({ id: model.slug, object: 'model', owned_by: 'z.ai' })),
      }));
      return;
    }
    if (req.method !== 'POST' || !['/responses', '/v1/responses'].includes(req.url || '')) {
      sendError(res, 404, 'not_found');
      return;
    }
    const apiKey = getApiKey(req);
    if (!apiKey) {
      sendError(res, 401, 'ZAI_API_KEY is missing. Set it as a Windows user environment variable.');
      return;
    }
    const body = await readJson(req);
    const requestedModel = typeof body.model === 'string' && body.model.length > 0 ? body.model : DEFAULT_MODEL;
    if (requestedModel !== DEFAULT_MODEL) {
      sendError(res, 400, `Unsupported Z.ai proxy model "${requestedModel}". Use the default OpenAI profile for OpenAI models.`);
      return;
    }
    const { payload, namespaces } = chatPayload(body);
    const upstream = await fetch(ZAI_CHAT_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify(payload),
    });
    if (!upstream.ok) {
      const text = await upstream.text();
      sendError(res, upstream.status, `Z.ai upstream ${upstream.status}: ${text.slice(0, 2000)}`);
      return;
    }
    if (payload.stream) {
      await proxyStream(res, upstream, payload.model, namespaces);
      return;
    }
    sendNonStreamResponse(res, await upstream.json(), payload.model, namespaces);
  } catch (err) {
    sendError(res, 500, err instanceof Error ? err.message : String(err));
  }
});

server.listen(PORT, HOST, () => {
  process.stdout.write(`zai-codex-responses-proxy listening on http://${HOST}:${PORT}\n`);
});
