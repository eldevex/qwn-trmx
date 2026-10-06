#!/data/data/com.termux/files/usr/bin/bash
#
# setup.sh — разворачивает Qwen API Proxy в Termux
#
# Использование:
#   bash <(curl -fsSL https://raw.githubusercontent.com/eldevex/qwn-trmx/main/setup.sh)
#   или
#   ./setup.sh [путь]
#
# По умолчанию создаёт всё в $HOME/qwen-proxy
#

set -e

PROJECT_DIR="${1:-$HOME/qwen-proxy}"

echo ""
echo "════════════════════════════════════════════════"
echo "  🌐 Qwen API Proxy — установка"
echo "════════════════════════════════════════════════"
echo ""
echo "📁 Проект будет создан в: $PROJECT_DIR"
echo ""

# ---- 1. Проверка/установка Node.js ----
if ! command -v node >/dev/null 2>&1; then
  echo "📦 Устанавливаю Node.js..."
  pkg update -y >/dev/null 2>&1 || true
  pkg install -y nodejs
else
  echo "✅ Node.js уже установлен: $(node -v)"
fi

# ---- 2. Создание директории ----
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# ---- 3. qwen-proxy.js ----
echo "📝 Создаю qwen-proxy.js..."
cat > qwen-proxy.js <<'PROXY_EOF'
#!/usr/bin/env node
// Qwen Web Chat → OpenAI-compatible API proxy (v7, финальная сборка)
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { URL } = require('url');

const PORT = Number(process.env.PORT) || 5000;
const HOST = process.env.HOST || '127.0.0.1';
const AUTH_FILE = path.join(__dirname, 'qwen-auth.json');
const DEBUG = process.env.DEBUG !== '0';

const REFRESH_INTERVAL_MS = Number(process.env.REFRESH_INTERVAL_MS) || 10 * 60 * 1000;
const REFRESH_AHEAD_SEC   = Number(process.env.REFRESH_AHEAD_SEC)   || 300;
const DEFAULT_MAX_TOKENS  = Number(process.env.DEFAULT_MAX_TOKENS)  || 32768;

const DEFAULT_MODEL = 'qwen3.7-plus';
const AVAILABLE_MODELS = [
  'qwen3.8-max', 'qwen3.7-max', 'qwen3.7-plus', 'qwen3.6-plus', 'qwen3.5-plus',
];

const UA = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/154.0.0.0 Mobile Safari/537.36';

let auth = null;
let refreshTimer = null;
let authWatcher = null;
let lastRefresh = { at: null, ok: null, error: null, strategy: null };

function loadAuth() {
  auth = JSON.parse(fs.readFileSync(AUTH_FILE, 'utf8'));
  if (!auth.token) throw new Error('token missing');
  if (!auth.cookie) throw new Error('cookie missing');
}
function saveAuth() {
  fs.writeFileSync(AUTH_FILE, JSON.stringify(auth, null, 2), { mode: 0o600 });
}
function uuid() { return crypto.randomUUID(); }
function decodeJwtExp(token) {
  try {
    const p = JSON.parse(Buffer.from(token.split('.')[1], 'base64').toString());
    return p.exp || 0;
  } catch (e) { return 0; }
}
function timezoneHeader() {
  const d = new Date();
  const days = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  const off = -d.getTimezoneOffset();
  const sign = off >= 0 ? '+' : '-';
  const abs = Math.abs(off);
  const hh = String(Math.floor(abs / 60)).padStart(2, '0');
  const mm = String(abs % 60).padStart(2, '0');
  const p = n => String(n).padStart(2, '0');
  return days[d.getDay()] + ' ' + months[d.getMonth()] + ' ' + p(d.getDate()) + ' ' +
         d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes()) + ':' +
         p(d.getSeconds()) + ' GMT' + sign + hh + mm;
}

function buildHeaders(extra = {}) {
  return {
    'accept': 'application/json',
    'accept-language': 'ru-RU,ru;q=0.9',
    'authorization': `Bearer ${auth.token}`,
    'cookie': auth.cookie,
    'content-type': 'application/json',
    'source': 'h5',
    'timezone': timezoneHeader(),
    'version': '0.3.12',
    'x-request-id': uuid(),
    'user-agent': UA,
    ...(auth.bx_ua        ? { 'bx-ua':        auth.bx_ua }        : {}),
    ...(auth.bx_umidtoken ? { 'bx-umidtoken': auth.bx_umidtoken } : {}),
    ...(auth.bx_v         ? { 'bx-v':         auth.bx_v }         : {}),
    ...extra,
  };
}

function buildRefreshHeaders() {
  return {
    'accept': 'application/json',
    'accept-language': 'ru-RU,ru;q=0.9',
    'cookie': auth.cookie,
    'source': 'h5',
    'timezone': timezoneHeader(),
    'version': '0.3.12',
    'x-request-id': uuid(),
    'origin': 'https://chat.qwen.ai',
    'referer': 'https://chat.qwen.ai/',
    'x-request-origin': 'https://chat.qwen.ai',
    'user-agent': UA,
    ...(auth.bx_ua        ? { 'bx-ua':        auth.bx_ua }        : {}),
    ...(auth.bx_umidtoken ? { 'bx-umidtoken': auth.bx_umidtoken } : {}),
    ...(auth.bx_v         ? { 'bx-v':         auth.bx_v }         : {}),
  };
}

function extractTokens(text) {
  try {
    const j = JSON.parse(text);
    const d = j?.data || j;
    const access  = d?.access_token  || d?.token;
    const refresh = d?.refresh_token;
    if (access && access.startsWith('eyJ')) {
      return { access, refresh: (refresh && refresh.startsWith('eyJ')) ? refresh : null };
    }
  } catch (e) {}
  const m = text.match(/eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+/g);
  if (m && m.length) return { access: m[0], refresh: m[1] || null };
  return null;
}

function updateCookieRefreshToken(cookieStr, newRefresh) {
  if (!newRefresh) return cookieStr;
  return cookieStr.split(';').map(p => p.trim())
    .map(p => p.startsWith('refresh_token=') ? 'refresh_token=' + newRefresh : p)
    .join('; ');
}

async function refreshToken() {
  if (!auth || !auth.token) return false;
  console.log('[auth] refreshing access token...');
  try {
    const res = await fetch('https://auth.qwen.ai/api/v2/auths/refresh', {
      method: 'GET',
      headers: buildRefreshHeaders(),
    });
    const text = await res.text();
    if (DEBUG) console.log('[auth] refresh HTTP', res.status, 'body:', text.slice(0, 400));

    if (res.ok) {
      const t = extractTokens(text);
      if (t && t.access) {
        auth.token = t.access;
        if (t.refresh) {
          auth.refresh_token = t.refresh;
          auth.cookie = updateCookieRefreshToken(auth.cookie, t.refresh);
          console.log('[auth] 🔄 refresh_token rotated, cookie updated');
        }
        saveAuth();
        const exp = decodeJwtExp(auth.token);
        lastRefresh = { at: Date.now(), ok: true, error: null, strategy: 'GET-refresh' };
        console.log(`[auth] ✅ token updated. exp: ${new Date(exp * 1000).toISOString()}`);
        return true;
      }
      console.warn('[auth] ⚠️  refresh OK, но токен не распарсился');
    }
  } catch (e) {
    console.error('[auth] refresh error:', e.message);
  }
  lastRefresh = { at: Date.now(), ok: false, error: 'refresh failed', strategy: null };
  console.warn('[auth] ⚠️  refresh failed, продолжаем со старым токеном');
  return false;
}

async function ensureFreshToken() {
  const exp = decodeJwtExp(auth.token);
  const now = Math.floor(Date.now() / 1000);
  if (exp && (exp - now) < REFRESH_AHEAD_SEC) {
    return await refreshToken();
  }
  return true;
}

function startRefreshTimer() {
  if (refreshTimer) clearInterval(refreshTimer);
  refreshTimer = setInterval(async () => {
    try { await refreshToken(); }
    catch (e) { console.error('[auth] periodic refresh error:', e.message); }
  }, REFRESH_INTERVAL_MS);
  if (refreshTimer.unref) refreshTimer.unref();
  console.log(`[auth] periodic refresh every ${Math.round(REFRESH_INTERVAL_MS / 60000)} min (ahead ${REFRESH_AHEAD_SEC}s)`);
}

function watchAuthFile() {
  if (authWatcher) return;
  try {
    authWatcher = fs.watch(AUTH_FILE, { persistent: false }, (eventType) => {
      if (eventType !== 'change') return;
      clearTimeout(watchAuthFile._t);
      watchAuthFile._t = setTimeout(() => {
        try {
          const newAuth = JSON.parse(fs.readFileSync(AUTH_FILE, 'utf8'));
          if (newAuth.token && newAuth.token !== auth.token) {
            auth = newAuth;
            const exp = decodeJwtExp(auth.token);
            console.log('[auth] 🔄 qwen-auth.json изменён, токен перезагружен. exp:',
              new Date(exp * 1000).toISOString());
          }
        } catch (e) {
          console.error('[auth] failed to reload auth file:', e.message);
        }
      }, 500);
    });
    console.log('[auth] watching qwen-auth.json for changes');
  } catch (e) {
    console.warn('[auth] could not watch auth file:', e.message);
  }
}

function flattenMessages(messages) {
  if (!messages || messages.length <= 1) return messages;
  const lastUserIdx = messages.map(m => m.role).lastIndexOf('user');
  if (lastUserIdx < 0) return messages.slice(-1);
  const history = messages.slice(0, lastUserIdx);
  const last = messages[lastUserIdx];
  const lastText = typeof last.content === 'string' ? last.content : JSON.stringify(last.content);
  if (!history.length) return [last];
  const historyText = history.map(m => {
    const txt = typeof m.content === 'string' ? m.content : JSON.stringify(m.content);
    return (m.role === 'user' ? 'Пользователь: ' : 'Ассистент: ') + txt;
  }).join('\n\n');
  return [{ role: 'user', content: historyText + '\n\nПользователь: ' + lastText }];
}

async function createChat(model) {
  await ensureFreshToken();
  const res = await fetch('https://chat.qwen.ai/api/v2/chats/new', {
    method: 'POST',
    headers: buildHeaders(),
    body: JSON.stringify({
      chatId: '',
      models: [model],
      project_id: '',
      timestamp: Math.floor(Date.now() / 1000),
      chat_type: 't2t',
      chat_mode: 'normal',
    }),
  });
  const text = await res.text();
  if (DEBUG) console.log('[createChat] HTTP', res.status, text.slice(0, 200));
  let j = null; try { j = JSON.parse(text); } catch (e) {}
  const id = j?.data?.id || j?.id;
  if (!id) throw new Error('createChat: no id in response: ' + text.slice(0, 200));
  return id;
}

async function qwenChat(messages, model, chatId, maxTokens) {
  await ensureFreshToken();
  messages = flattenMessages(messages);
  const now = Math.floor(Date.now() / 1000);
  const childId = uuid();

  const body = {
    stream: true,
    version: '2.1',
    incremental_output: true,
    chatId,
    parentId: '',
    chat_id: chatId,
    chat_mode: 'normal',
    model,
    parent_id: null,
    max_tokens: maxTokens,
    messages: messages.map((m) => ({
      id: null,
      fid: uuid(),
      parentId: null,
      childrenIds: [childId],
      role: m.role,
      content: typeof m.content === 'string' ? m.content : JSON.stringify(m.content),
      user_action: m.role === 'user' ? 'chat' : undefined,
      files: [],
      timestamp: now,
      models: [model],
      model: '',
      chat_type: 't2t',
      feature_config: {
        thinking_enabled: true,
        output_schema: 'phase',
        research_mode: 'normal',
        auto_thinking: true,
        thinking_mode: 'Auto',
        thinking_format: 'summary',
        auto_search: true,
      },
      extra: { meta: { subChatType: 't2t' } },
      sub_chat_type: 't2t',
      parent_id: null,
    })),
    timestamp: now,
  };

  const url = `https://chat.qwen.ai/api/v2/chat/completions?chat_id=${chatId}`;
  return await fetch(url, {
    method: 'POST',
    headers: buildHeaders({ 'x-accel-buffering': 'no' }),
    body: JSON.stringify(body),
  });
}

async function* parseQwenStream(res) {
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() || '';
    for (const line of lines) {
      if (!line.startsWith('data: ')) continue;
      const payload = line.slice(6).trim();
      if (!payload || payload === '[DONE]') continue;
      try {
        const data = JSON.parse(payload);
        const delta = data?.choices?.[0]?.delta;
        if (delta) yield delta;
      } catch (e) {}
    }
  }
}

async function handleQwenResponse(qres, res, model, stream) {
  if (stream) {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    });
    const id = 'chatcmpl-' + uuid();
    const created = Math.floor(Date.now() / 1000);
    res.write(`data: ${JSON.stringify({
      id, object: 'chat.completion.chunk', created, model,
      choices: [{ index: 0, delta: { role: 'assistant' }, finish_reason: null }],
    })}\n\n`);
    let chars = 0;
    for await (const delta of parseQwenStream(qres)) {
      const content = delta.content || '';
      if (delta.phase === 'answer' && content) {
        chars += content.length;
        res.write(`data: ${JSON.stringify({
          id, object: 'chat.completion.chunk', created, model,
          choices: [{ index: 0, delta: { content }, finish_reason: null }],
        })}\n\n`);
      }
      if (delta.status === 'finished' && delta.phase === 'answer') {
        res.write(`data: ${JSON.stringify({
          id, object: 'chat.completion.chunk', created, model,
          choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
        })}\n\n`);
      }
    }
    res.write('data: [DONE]\n\n');
    res.end();
    console.log(`[qwen] ✅ stream done, ${chars} chars`);
  } else {
    let content = '';
    let lastPhase = '';
    for await (const delta of parseQwenStream(qres)) {
      if (delta.phase) lastPhase = delta.phase;
      if (delta.phase === 'answer' && delta.content) content += delta.content;
    }
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      id: 'chatcmpl-' + uuid(),
      object: 'chat.completion',
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: 'stop' }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
    }));
    console.log(`[qwen] ✅ response, ${content.length} chars (last phase: ${lastPhase})`);
  }
}

const server = http.createServer(async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }

  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (url.pathname === '/v1/models') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      object: 'list',
      data: AVAILABLE_MODELS.map(id => ({ id, object: 'model', created: 1700000000, owned_by: 'qwen' })),
    }));
    return;
  }

  if (url.pathname === '/v1/health') {
    const exp = decodeJwtExp(auth.token);
    const nowSec = Math.floor(Date.now() / 1000);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      ok: true,
      token_expires_at: exp ? new Date(exp * 1000).toISOString() : null,
      token_expired: exp ? (exp < nowSec) : null,
      token_seconds_left: exp ? Math.max(0, exp - nowSec) : null,
      has_refresh_token: !!auth.refresh_token,
      has_bx_ua: !!auth.bx_ua,
      user_id: auth.user_id || null,
      last_refresh: lastRefresh,
      refresh_interval_ms: REFRESH_INTERVAL_MS,
      refresh_ahead_sec: REFRESH_AHEAD_SEC,
      default_max_tokens: DEFAULT_MAX_TOKENS,
    }));
    return;
  }

  if (url.pathname === '/v1/refresh' && req.method === 'POST') {
    const ok = await refreshToken();
    res.writeHead(ok ? 200 : 502, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok, last_refresh: lastRefresh }));
    return;
  }

  if (url.pathname === '/v1/chat/completions' && req.method === 'POST') {
    let body = '';
    req.on('data', c => body += c);
    req.on('end', async () => {
      try {
        const params = JSON.parse(body || '{}');
        const messages = params.messages || [];
        const model = String(params.model || DEFAULT_MODEL);
        const stream = params.stream === true;
        const maxTokens = Number(params.max_tokens) || DEFAULT_MAX_TOKENS;

        if (!messages.length) {
          res.writeHead(400, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: 'messages required' } }));
          return;
        }

        console.log(`[qwen] → model=${model} msgs=${messages.length} stream=${stream} max_tokens=${maxTokens}`);

        const chatId = await createChat(model);
        console.log(`[qwen] chat created: ${chatId}`);

        let qres = await qwenChat(messages, model, chatId, maxTokens);

        if (qres.status === 401) {
          console.warn('[qwen] 401 — refresh и повтор');
          const ok = await refreshToken();
          if (ok) {
            const chatId2 = await createChat(model);
            qres = await qwenChat(messages, model, chatId2, maxTokens);
          }
        }

        if (!qres.ok) {
          const t = await qres.text();
          console.error(`[qwen] HTTP ${qres.status}:`, t.slice(0, 400));
          res.writeHead(qres.status, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: t.slice(0, 500) } }));
          return;
        }

        await handleQwenResponse(qres, res, model, stream);
      } catch (e) {
        console.error('[err]', e.stack || e.message);
        if (!res.headersSent) {
          res.writeHead(500, { 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: { message: String(e.message || e) } }));
        }
      }
    });
    return;
  }

  res.writeHead(404); res.end('Not found');
});

function shutdown() {
  if (refreshTimer) clearInterval(refreshTimer);
  if (authWatcher) authWatcher.close();
  process.exit(0);
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);

loadAuth();
startRefreshTimer();
watchAuthFile();

server.listen(PORT, HOST, () => {
  const exp = decodeJwtExp(auth.token);
  console.log(`[qwen-proxy] listening on http://${HOST}:${PORT}`);
  console.log(`[qwen-proxy] models: ${AVAILABLE_MODELS.join(', ')}`);
  console.log(`[qwen-proxy] token exp: ${exp ? new Date(exp * 1000).toISOString() : 'unknown'}${exp && exp * 1000 < Date.now() ? ' (EXPIRED)' : ''}`);
  console.log(`[qwen-proxy] refresh_token: ${auth.refresh_token ? 'yes (' + auth.refresh_token.length + ' chars)' : 'NO'}`);
  console.log(`[qwen-proxy] bx-ua: ${auth.bx_ua ? 'yes' : 'NO'}`);
  console.log(`[qwen-proxy] default max_tokens: ${DEFAULT_MAX_TOKENS}`);
  console.log(`[qwen-proxy] DEBUG: ${DEBUG ? 'on' : 'off'}`);
});
PROXY_EOF

# ---- 4. extract-qwen-auth.js ----
echo "📝 Создаю extract-qwen-auth.js..."
cat > extract-qwen-auth.js <<'EXTRACT_EOF'
#!/usr/bin/env node
// Извлекает qwen-auth.json из дампа Qwen Full Dumper
const fs = require('fs');
const path = require('path');

const dumpFile = process.argv[2];
if (!dumpFile) {
  console.error('Usage: node extract-qwen-auth.js <qwen-dump.json>');
  process.exit(1);
}

const dump = JSON.parse(fs.readFileSync(dumpFile, 'utf8'));
const ls = dump.localStorage || {};

const token = ls.token || '';
const cookieParts = [];
let refresh_token = '';
for (const c of (dump.cookies || [])) {
  cookieParts.push(`${c.name}=${c.value}`);
  if (c.name === 'refresh_token') refresh_token = c.value;
}

let bx_ua = '', bx_umidtoken = '', bx_v = '', device_id = '';
const requests = dump.capturedRequests || [];
for (let i = requests.length - 1; i >= 0; i--) {
  const r = requests[i];
  const h = r.headers || {};
  const isChat = r.url && (r.url.includes('/chat/completions') || r.url.includes('/chat_session'));
  if (isChat && h['bx-ua']) {
    bx_ua = h['bx-ua'];
    bx_umidtoken = h['bx-umidtoken'] || '';
    bx_v = h['bx-v'] || '';
    break;
  }
}
if (!bx_ua) {
  for (const r of requests) {
    const h = r.headers || {};
    if (h['bx-ua'] && !bx_ua) bx_ua = h['bx-ua'];
    if (h['bx-umidtoken'] && !bx_umidtoken) bx_umidtoken = h['bx-umidtoken'];
    if (h['bx-v'] && !bx_v) bx_v = h['bx-v'];
    if (h['x-device-id'] && !device_id) device_id = h['x-device-id'];
  }
}

const cnaui = ls.cnaui || '';
const result = {
  token,
  refresh_token,
  cookie: cookieParts.join('; '),
  bx_ua,
  bx_umidtoken,
  bx_v: bx_v || '2.5.37',
  user_id: cnaui,
  device_id,
};

const outFile = path.join(path.dirname(dumpFile), 'qwen-auth.json');
fs.writeFileSync(outFile, JSON.stringify(result, null, 2), { mode: 0o600 });

console.log('✅ qwen-auth.json: ' + outFile);
console.log('   token:         ' + (token ? token.slice(0, 40) + '...' : '(ПУСТО)'));
console.log('   refresh_token: ' + (refresh_token ? refresh_token.slice(0, 40) + '...' : '(ПУСТО)'));
console.log('   cookie:        ' + cookieParts.length + ' cookies, ' + result.cookie.length + ' chars');
console.log('   bx-ua:         ' + (bx_ua ? bx_ua.slice(0, 50) + '...' : '(ПУСТО)'));
console.log('   bx-umidtoken:  ' + (bx_umidtoken ? bx_umidtoken.slice(0, 50) + '...' : '(ПУСТО)'));
console.log('   bx-v:          ' + (bx_v || '(ПУСТО)'));
console.log('   user_id:       ' + (cnaui || '(ПУСТО)'));
EXTRACT_EOF

# ---- 5. start-qwen.sh ----
echo "📝 Создаю start-qwen.sh..."
cat > start-qwen.sh <<'START_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"

pkill -f "qwen-proxy.js" 2>/dev/null
sleep 1

REFRESH_INTERVAL_MS=600000 REFRESH_AHEAD_SEC=300 DEFAULT_MAX_TOKENS=32768 \
  nohup node qwen-proxy.js > proxy.log 2>&1 &

echo "✅ qwen-proxy запущен, PID $!"
echo ""
echo "Проверка:        curl http://localhost:5000/v1/health"
echo "Ручной refresh:  curl -X POST http://localhost:5000/v1/refresh"
echo "Логи:            tail -f $(dirname "$0")/proxy.log"
echo "Стоп:            pkill -f qwen-proxy.js"
START_EOF

# ---- 6. update-auth.sh ----
echo "📝 Создаю update-auth.sh..."
cat > update-auth.sh <<'UPD_EOF'
#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
if [ -z "$1" ]; then
  echo "Usage: $0 <qwen-dump.json>"
  exit 1
fi
if [ ! -f "$1" ]; then
  echo "❌ Файл не найден: $1"
  exit 1
fi
cp "$1" ./dump-tmp.json
chmod 644 ./dump-tmp.json
node extract-qwen-auth.js dump-tmp.json
rm -f ./dump-tmp.json
echo "ℹ️  Прокси подхватит новый токен автоматически (fs.watch)."
UPD_EOF

# ---- 7. .gitignore ----
echo "📝 Создаю .gitignore..."
cat > .gitignore <<'GI_EOF'
qwen-auth.json
proxy.log
qwen-dump-*.json
dump-tmp.json
node_modules/
GI_EOF

# ---- 8. Права ----
chmod +x qwen-proxy.js extract-qwen-auth.js start-qwen.sh update-auth.sh setup.sh 2>/dev/null || true
chmod +x qwen-proxy.js extract-qwen-auth.js start-qwen.sh update-auth.sh

# ---- 9. Итог ----
echo ""
echo "════════════════════════════════════════════════"
echo "  ✅ Установка завершена"
echo "════════════════════════════════════════════════"
echo ""
echo "📁 Проект: $PROJECT_DIR"
echo ""
ls -la "$PROJECT_DIR" | grep -v "^total"
echo ""
echo "════════════════════════════════════════════════"
echo "  Что дальше"
echo "════════════════════════════════════════════════"
echo ""
echo "  1️⃣  Установи расширение из папки extension/ в Kiwi или Titanium"
echo "      браузере (Load unpacked → выбрать папку extension/)"
echo ""
echo "  2️⃣  Открой chat.qwen.ai, залогинься и сними дамп через расширение"
echo ""
echo "  3️⃣  Положи дамп в $PROJECT_DIR и выполни:"
echo ""
echo "        cd $PROJECT_DIR"
echo "        ./update-auth.sh qwen-dump-XXXX.json"
echo ""
echo "  4️⃣  Запусти прокси:"
echo ""
echo "        ./start-qwen.sh"
echo ""
echo "  5️⃣  Проверь:"
echo ""
echo "        curl http://localhost:5000/v1/health"
echo ""
echo "  📱 В Kai 9000 укажи: http://127.0.0.1:5000/v1"
echo "  🎯 Рекомендуемая модель: qwen3.7-plus"
echo ""
echo "════════════════════════════════════════════════"
