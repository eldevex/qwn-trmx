#!/data/data/com.termux/files/usr/bin/bash
cd "$(dirname "$0")"
if [ -z "$1" ]; then
  echo "Usage: $0 <qwen-dump.json>"
  exit 1
fi
cp "$1" ./dump-tmp.json
chmod 644 ./dump-tmp.json
node extract-qwen-auth.js dump-tmp.json
rm -f ./dump-tmp.json
echo "ℹ️  Прокси подхватит новый токен автоматически (fs.watch)."
