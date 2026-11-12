// One public HTTPS URL for the local backend, so a physical phone can reach it
// from any network (office WiFi blocks device-to-device; iOS blocks plain HTTP).
//
// Supabase paths -> local Supabase :54321, everything else -> local web :3000.
// Both halves stay one stack, which AppConfig requires (same token on both).
//
// Usage: tool/dev_tunnel.sh   (starts this proxy on :8080 + ngrok)
// Then:  flutter run --dart-define-from-file=env.local.ngrok.json
//        with SUPABASE_URL and APP_URL both set to the ngrok URL.
const SUPA = 'http://127.0.0.1:54321';
const WEB = 'http://127.0.0.1:3000';
const SUPA_PREFIXES = ['/auth/v1', '/rest/v1', '/realtime/v1', '/storage/v1', '/functions/v1', '/graphql/v1'];

const upstream = (path) =>
  SUPA_PREFIXES.some((p) => path === p || path.startsWith(p + '/')) ? SUPA : WEB;

Bun.serve({
  port: 8080,
  async fetch(req, server) {
    const url = new URL(req.url);
    const base = upstream(url.pathname);
    const target = base + url.pathname + url.search;

    // Realtime websocket: bridge to the upstream socket.
    if (req.headers.get('upgrade')?.toLowerCase() === 'websocket') {
      const ok = server.upgrade(req, { data: { target: target.replace(/^http/, 'ws'), queue: [] } });
      return ok ? undefined : new Response('websocket upgrade failed', { status: 400 });
    }

    const headers = new Headers(req.headers);
    headers.delete('host');
    headers.set('x-forwarded-host', url.host);
    headers.set('x-forwarded-proto', 'https');
    try {
      const res = await fetch(target, {
        method: req.method,
        headers,
        body: req.method === 'GET' || req.method === 'HEAD' ? undefined : req.body,
        redirect: 'manual',
        duplex: 'half',
        decompress: true,
      });
      const out = new Headers(res.headers);
      // fetch already decompressed the body.
      out.delete('content-encoding');
      out.delete('content-length');
      console.log(`${req.method} ${url.pathname} -> ${base === SUPA ? 'supabase' : 'web'} ${res.status}`);
      return new Response(res.body, { status: res.status, headers: out });
    } catch (e) {
      console.log(`${req.method} ${url.pathname} -> ${base === SUPA ? 'supabase' : 'web'} ERROR ${e}`);
      return new Response(`upstream unreachable: ${base}`, { status: 502 });
    }
  },
  websocket: {
    open(ws) {
      const up = new WebSocket(ws.data.target);
      ws.data.up = up;
      up.onopen = () => {
        for (const m of ws.data.queue) up.send(m);
        ws.data.queue = [];
      };
      up.onmessage = (e) => ws.send(e.data);
      up.onclose = () => ws.close();
      up.onerror = () => ws.close();
    },
    message(ws, msg) {
      const up = ws.data.up;
      if (up.readyState === 1) up.send(msg);
      else ws.data.queue.push(msg);
    },
    close(ws) {
      ws.data.up?.close();
    },
  },
});
console.log('dev-proxy on :8080 (supabase :54321, web :3000)');
