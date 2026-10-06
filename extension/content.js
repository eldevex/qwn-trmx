const reqBuffer = [];

function dumpStorage(storage) {
  const out = {};
  try {
    for (let i = 0; i < storage.length; i++) {
      const k = storage.key(i);
      out[k] = storage.getItem(k);
    }
  } catch (e) {}
  return out;
}

function patchStorage(key, patch) {
  chrome.storage.local.get(key, (r) => {
    const cur = r[key] || {};
    chrome.storage.local.set({ [key]: Object.assign({}, cur, patch, { _updated: Date.now() }) });
  });
}

// Первичный дамп storage
patchStorage("qw_dump", {
  url: location.href,
  userAgent: navigator.userAgent,
  localStorage: dumpStorage(localStorage),
  sessionStorage: dumpStorage(sessionStorage),
});

// Перечитываем через 3 и 8 секунд
setTimeout(() => patchStorage("qw_dump", {
  localStorage: dumpStorage(localStorage),
  sessionStorage: dumpStorage(sessionStorage),
}), 3000);
setTimeout(() => patchStorage("qw_dump", {
  localStorage: dumpStorage(localStorage),
  sessionStorage: dumpStorage(sessionStorage),
}), 8000);

// Приём запросов от injector
window.addEventListener("message", (e) => {
  if (e.source !== window) return;
  const d = e.data;
  if (!d || d.__qw !== "req" || !d.entry) return;
  reqBuffer.push(d.entry);
  if (reqBuffer.length > 300) reqBuffer.shift();
});

// Раз в секунду сливаем буфер в storage
setInterval(() => {
  if (!reqBuffer.length) return;
  chrome.storage.local.get("qw_dump", (r) => {
    const cur = r.qw_dump || {};
    const reqs = (cur.capturedRequests || []).concat(reqBuffer.splice(0));
    if (reqs.length > 300) reqs.splice(0, reqs.length - 300);
    cur.capturedRequests = reqs;
    cur._updated = Date.now();
    chrome.storage.local.set({ qw_dump: cur });
  });
}, 1000);

// Ответ на команду очистки
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg && msg.action === "clearCaptured") {
    reqBuffer.length = 0;
    chrome.storage.local.get("qw_dump", (r) => {
      const cur = r.qw_dump || {};
      cur.capturedRequests = [];
      chrome.storage.local.set({ qw_dump: cur }, () => sendResponse({ ok: true }));
    });
    return true;
  }
});