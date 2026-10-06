<div align="center">

# 🌐 Qwen API Proxy

**OpenAI-совместимый API для Qwen Web Chat через Termux**

Локальный сервер, который превращает браузерную сессию `chat.qwen.ai` в стандартный OpenAI-совместимый API. Работает с Kai 9000, Open WebUI, Chatbox, SillyTavern, OpenAI SDK и другими клиентами.

[![Termux](https://img.shields.io/badge/Termux-F--Droid-000000?style=flat-square&logo=android&logoColor=white)](https://f-droid.org/packages/com.termux/)
[![Node.js](https://img.shields.io/badge/Node.js-18%2B-339933?style=flat-square&logo=node.js&logoColor=white)](https://nodejs.org/)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?style=flat-square&logo=android&logoColor=white)](#)

### 📖 [**Открыть веб-инструкцию →**](https://eldevex.github.io/qwn-trmx/)

Красивая пошаговая инструкция с примерами, скриншотами и FAQ — то же самое, что в этом README, но удобнее для чтения с телефона.

</div>

---

> [!WARNING]
> **Используйте на свой страх и риск.** Проект работает через недокументированный web-API Qwen. Это может нарушать условия использования и привести к блокировке аккаунта. Автор не несёт ответственности за заблокированные аккаунты, неверные ответы модели или любые другие последствия. Используйте одноразовый аккаунт, который не жалко потерять.

---

## ✨ Возможности

- 🔌 **OpenAI-совместимый API** на `127.0.0.1:5000`
- 🎯 **Поддержка 5 моделей**: `qwen3.8-max`, `qwen3.7-max`, `qwen3.7-plus`, `qwen3.6-plus`, `qwen3.5-plus`
- 🌊 **SSE-стриминг** — работает в реальном времени
- 🔄 **Автообновление токена** — каждые 10 минут + за 5 минут до истечения
- ♻️ **Ротация `refresh_token`** — прокси сам сохраняет новый токен и cookie
- 👀 **`fs.watch`** — автоматически подхватывает новый auth-файл без перезапуска
- 🧩 **Расширение для снятия дампа** — встроено в репозиторий
- 🪶 **Минимум зависимостей** — только встроенные модули Node.js

---

## 📋 Требования

| Компонент | Что нужно |
|---|---|
| **Устройство** | Android 8+ |
| **Терминал** | [Termux из F-Droid](https://f-droid.org/packages/com.termux/) (не из Google Play!) |
| **Node.js** | 18+ (устанавливается автоматически) |
| **Браузер** | Любой Chromium-браузер с поддержкой расширений: [Kiwi Browser](https://play.google.com/store/apps/details?id=com.kiwibrowser.browser) или [Titanium Browser](https://github.com/jqssun/android-titanium-browser) |
| **Аккаунт** | Qwen (одноразовый, не основной) |

---

## 🚀 Установка

> 💡 **Совет:** если предпочитаете читать с телефона — откройте [веб-инструкцию](https://eldevex.github.io/qwn-trmx/) — там то же самое, но с более удобной вёрсткой.

### Способ 1: Bash-скрипт (быстрый)

Скопируйте и вставьте в Termux:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/eldevex/qwn-trmx/main/setup.sh)
```

Или скопируйте содержимое `setup.sh` из репозитория и вставьте в терминал целиком.

### Способ 2: Клонирование репозитория (классический)

```bash
cd ~
git clone https://github.com/eldevex/qwn-trmx.git
cd qwn-trmx
npm install
```

### Что дальше — одинаково для обоих способов

<details>
<summary><b>1️⃣ Установите расширение в браузере</b></summary>

1. Откройте папку `extension/` из репозитория — там лежит расширение для снятия дампа.
2. Откройте **Kiwi** или **Titanium Browser**.
3. Включите **Режим разработчика** в разделе расширений.
4. Нажмите **Load unpacked** и выберите папку `extension/`.
5. Иконка расширения появится на панели.

</details>

<details>
<summary><b>2️⃣ Сделайте дамп auth</b></summary>

1. Откройте `chat.qwen.ai` в том же браузере.
2. Залогиньтесь в аккаунт.
3. Нажмите иконку расширения → **Dump**.
4. Сохраните полученный файл `qwen-dump-XXXXX.json`.

</details>

<details>
<summary><b>3️⃣ Загрузите дамп в прокси</b></summary>

```bash
cd ~/qwen-proxy
cp ~/storage/downloads/qwen-dump-XXXXX.json .
chmod 644 qwen-dump-XXXXX.json
./update-auth.sh qwen-dump-XXXXX.json
```

Скрипт распарсит дамп и создаст `qwen-auth.json`. В консоли увидите:

```
✅ qwen-auth.json: qwen-auth.json
   token:         eyJhbGciOiJIUzI1NiIs...
   refresh_token: eyJhbGciOiJIUzI1NiIs...
   cookie:        10 cookies, 716 chars
   bx-ua:         234!tFreKFaXeePWgnA3wjLkDBsIt...
```

</details>

<details>
<summary><b>4️⃣ Запустите прокси</b></summary>

```bash
./start-qwen.sh
```

Вывод:

```
✅ qwen-proxy запущен, PID 2607

Проверка:        curl http://localhost:5000/v1/health
Ручной refresh:  curl -X POST http://localhost:5000/v1/refresh
Логи:            tail -f ./proxy.log
Стоп:            pkill -f qwen-proxy.js
```

</details>

<details>
<summary><b>5️⃣ Проверьте работу</b></summary>

```bash
# Health check
curl -s http://localhost:5000/v1/health | python3 -m json.tool

# Тестовый запрос
curl -s http://localhost:5000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"qwen3.7-plus","messages":[{"role":"user","content":"привет"}]}' \
  | python3 -m json.tool
```

В health должно быть:
- `token_expired: false`
- `token_seconds_left` — порядка 800–900
- `has_refresh_token: true`

</details>

---

## 📱 Настройка клиента (Kai 9000 и др.)

В настройках клиента укажите:

| Параметр | Значение |
|---|---|
| **Base URL** | `http://127.0.0.1:5000/v1` |
| **API Key** | `sk-qwen` (любой — прокси не проверяет) |
| **Model** | `qwen3.7-plus` (рекомендуется) |

**Доступные модели:**

| ID модели | Описание |
|---|---|
| `qwen3.8-max` | Флагман Qwen3.8, reasoning |
| `qwen3.7-max` | Флагман Qwen3.7, reasoning |
| `qwen3.7-plus` | ✅ Стабильнее всего |
| `qwen3.6-plus` | Qwen3.6, лёгкая |
| `qwen3.5-plus` | Qwen3.5, лёгкая |

---

## 🛠 Управление

```bash
# Запуск
cd ~/qwen-proxy && ./start-qwen.sh

# Остановка
pkill -f qwen-proxy.js

# Логи в реальном времени
tail -f ~/qwen-proxy/proxy.log

# Состояние
curl -s http://localhost:5000/v1/health | python3 -m json.tool

# Ручной refresh токена
curl -X POST http://localhost:5000/v1/refresh

# Список моделей
curl -s http://localhost:5000/v1/models | python3 -m json.tool

# Проверить процесс
ps aux | grep qwen-proxy
```

---

## ⚙️ Настройки (переменные окружения)

Все параметры передаются при запуске:

```bash
REFRESH_INTERVAL_MS=600000 \
REFRESH_AHEAD_SEC=300 \
DEFAULT_MAX_TOKENS=32768 \
HOST=127.0.0.1 \
  nohup node qwen-proxy.js > proxy.log 2>&1 &
```

| Переменная | По умолчанию | Описание |
|---|---|---|
| `PORT` | `5000` | Порт сервера |
| `HOST` | `127.0.0.1` | Адрес прослушивания. Поставьте `0.0.0.0`, если подключаетесь с другого устройства |
| `REFRESH_INTERVAL_MS` | `600000` (10 мин) | Как часто обновлять access-токен |
| `REFRESH_AHEAD_SEC` | `300` (5 мин) | За сколько секунд до истечения обновлять |
| `DEFAULT_MAX_TOKENS` | `32768` | Лимит вывода, если клиент не передал свой |
| `DEBUG` | `1` | Включить подробные логи (`0` — выключить) |

---

## 🔄 Обновление токена

Access-токен обновляется автоматически. Но `refresh_token` живёт ~30 дней — после этого нужен новый дамп.

**Признаки того, что пора обновить:**

```
[auth] refresh HTTP 200 body: {"success":false,"data":{"code":"Unauthorized","details":"Токен отозван. Пожалуйста, войдите снова."}}
```

**Что делать:**

1. Откройте `chat.qwen.ai` в браузере, залогиньтесь заново.
2. Снимите свежий дамп через расширение.
3. Выполните:
   ```bash
   cd ~/qwen-proxy
   cp ~/storage/downloads/qwen-dump-XXXXX.json .
   ./update-auth.sh qwen-dump-XXXXX.json
   ```
4. Прокси подхватит токен **автоматически** — перезапуск не нужен.

---

## ❓ Частые проблемы

<details>
<summary><b>Прокси отвечает пустотой (content: "")</b></summary>

Причина: у reasoning-моделей (Max) think-блок съедает весь лимит токенов.

Решение: поднять `DEFAULT_MAX_TOKENS` или использовать `qwen3.7-plus`.

```bash
DEFAULT_MAX_TOKENS=65536 ./start-qwen.sh
```
</details>

<details>
<summary><b>Bad_Request: Invalid input too many messages</b></summary>

Причина: Qwen не принимает массив из нескольких сообщений. История должна быть вложена в одно сообщение. Прокси v7 решает это автоматически через `flattenMessages`.
</details>

<details>
<summary><b>Bad_Request: Missing origin при refresh</b></summary>

Причина: в заголовках refresh-запроса нет `origin`. Проверьте, что в `qwen-proxy.js` в `buildRefreshHeaders()` есть:

```javascript
'origin': 'https://chat.qwen.ai',
'referer': 'https://chat.qwen.ai/',
'x-request-origin': 'https://chat.qwen.ai',
```
</details>

<details>
<summary><b>Расширение не устанавливается в браузер</b></summary>

- Убедитесь, что используете Chromium-браузер с поддержкой расширений (**Kiwi Browser** или **Titanium Browser**) — в обычном Chrome на Android расширения не поддерживаются.
- Включите **Режим разработчика** в настройках расширений.
- При «Load unpacked» выбирайте папку `extension/`, а не файл внутри неё.
</details>

<details>
<summary><b>Kai не подключается, запросы не доходят</b></summary>

1. Прокси запущен? `ps aux | grep qwen-proxy`
2. Health отвечает? `curl -s http://127.0.0.1:5000/v1/health`
3. URL в клиенте: `http://127.0.0.1:5000/v1` (не `https`)
4. Смотрите лог: `tail -n 30 ~/qwen-proxy/proxy.log`
</details>

<details>
<summary><b>Termux убивается Android'ом</b></summary>

- Дайте Termux разрешение «Автозапуск» в настройках Android.
- Отключите оптимизацию батареи для Termux.
- Заблокируйте Termux в недавних приложениях, чтобы Android не выгружал его.
</details>

---

## 📂 Структура репозитория

```
qwn-trmx/
├── extension/                 # Расширение для снятия дампа (Qwen Full Dumper)
│   ├── manifest.json
│   ├── background.js
│   ├── content.js
│   └── icons/
├── qwen-proxy.js              # Сам прокси (Node.js)
├── extract-qwen-auth.js       # Парсер дампа → qwen-auth.json
├── start-qwen.sh              # Запуск прокси
├── update-auth.sh             # Обновление auth из нового дампа
├── setup.sh                   # Скрипт автоустановки
├── index.html                 # Веб-инструкция (GitHub Pages)
├── .gitignore
└── README.md
```

---

## ⚠️ Ограничения

- История диалога каждый раз вкладывается в одно сообщение — расходует больше токенов, чем «нативный» чат.
- `refresh_token` живёт ~30 дней. После — нужен новый дамп.
- `bx-ua` / `bx-umidtoken` не обновляются автоматически — берутся из дампа.
- Прокси не запускается после перезагрузки телефона — нужно запускать вручную.

---

## 🤝 Вклад

Нашли баг или есть идея? Открывайте [Issue](https://github.com/eldevex/qwn-trmx/issues) или присылайте Pull Request.

---

## 📜 Лицензия

MIT — используйте, модифицируйте, распространяйте. Ответственность за последствия — на вас.

---

<div align="center">

### 📖 [**Открыть веб-инструкцию →**](https://eldevex.github.io/qwn-trmx/)

**Сделано для личного использования. Используйте ответственно.**

⭐ Если проект оказался полезен — поставьте звезду!

</div>
