(function () {
  const MAX_BODY = 20000;
  const log = [];

  function truncate(s) {
    if (typeof s !== "string") return s;
    return s.length > MAX_BODY ? s.slice(0, MAX_BODY) + "...[truncated]" : s;
  }

  function headersToObj(h) {
    const out = {};
    try {
      if (!h) return out;
      if (h instanceof Headers) h.forEach((v, k) => out[k.toLowerCase()] = v);
      else if (Array.isArray(h)) h.forEach(([k, v]) => out[k.toLowerCase()] = v);
      else Object.keys(h).forEach(k => out[k.toLowerCase()] = h[k]);
    } catch (e) {}
    return out;
  }

  function interesting(url) {
    return typeof url === "string" && (
      url.includes("qwen") ||
      url.includes("/api/") ||
      url.includes("aliyun")
    );
  }

  function push(entry) {
    entry.ts = new Date().toISOString();
    log.push(entry);
    if (log.length > 300) log.shift();
    window.postMessage({ __qw: "req", entry }, "*");
  }

  // fetch
  const _f = window.fetch;
  window.fetch = function (input, init) {
    let url = "", method = "GET", headers = {}, body = "";
    try {
      url = typeof input === "string" ? input : (input && input.url) || "";
      method = (init && init.method) || (input && input.method) || "GET";
      headers = headersToObj((init && init.headers) || (input && input.headers));
      let b = init && init.body;
      if (b && typeof b !== "string") { try { b = JSON.stringify(b); } catch (e) { b = String(b); } }
      body = truncate(b || "");
      if (interesting(url)) push({ kind: "fetch.request", url, method, headers, body });
    } catch (e) {}

    const p = _f.apply(this, arguments);
    p.then(res => {
      try {
        if (interesting(url)) {
          const clone = res.clone();
          clone.text().then(t => push({
            kind: "fetch.response",
            url, status: res.status,
            headers: headersToObj(res.headers),
            body: truncate(t)
          })).catch(() => {});
        }
      } catch (e) {}
    }).catch(() => {});
    return p;
  };

  // XHR
  const _X = window.XMLHttpRequest;
  function W() {
    const xhr = new _X();
    const _open = xhr.open, _send = xhr.send, _setHeader = xhr.setRequestHeader;
    let method, url, headers = {};
    xhr.open = function (m, u) { method = m; url = u; return _open.apply(xhr, arguments); };
    xhr.setRequestHeader = function (k, v) { headers[k.toLowerCase()] = v; return _setHeader.apply(xhr, arguments); };
    xhr.send = function (body) {
      try {
        if (interesting(url)) {
          let b = body;
          if (b && typeof b !== "string") { try { b = JSON.stringify(b); } catch (e) { b = String(b); } }
          push({ kind: "xhr.request", url, method, headers, body: truncate(b || "") });
          xhr.addEventListener("load", () => push({
            kind: "xhr.response", url, status: xhr.status,
            body: truncate(xhr.responseText || "")
          }));
        }
      } catch (e) {}
      return _send.apply(xhr, arguments);
    };
    return xhr;
  }
  W.prototype = _X.prototype;
  window.XMLHttpRequest = W;
})();