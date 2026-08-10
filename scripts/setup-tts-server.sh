#!/usr/bin/env bash
# Instala a voz "Hope Velvet" no servidor privado de IA.
# A variante CPU é intencional: evita disputar VRAM com Ollama e XTTS.
set -euo pipefail

name="${TTS_CONTAINER_NAME:-hope-kokoro-tts}"
port="${TTS_PORT:-8880}"
image="${TTS_IMAGE:-ghcr.io/remsky/kokoro-fastapi-cpu:v0.6.0}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker não está instalado." >&2
  exit 1
fi

if docker container inspect "$name" >/dev/null 2>&1; then
  if [ "${TTS_RECREATE:-false}" = "true" ]; then
    docker rm -f "$name" >/dev/null
  else
    docker start "$name" >/dev/null || true
  fi
fi

if ! docker container inspect "$name" >/dev/null 2>&1; then
  docker run -d \
    --name "$name" \
    --restart unless-stopped \
    --env API_LOG_LEVEL=WARNING \
    -p "${port}:8880" \
    "$image" >/dev/null
fi

echo "Aguardando a voz Hope Velvet..."
for attempt in $(seq 1 90); do
  if curl --silent --fail "http://127.0.0.1:${port}/health" >/dev/null; then
    break
  fi
  if [ "$attempt" -eq 90 ]; then
    echo "O serviço não ficou pronto. Consulte: docker logs $name" >&2
    exit 1
  fi
  sleep 2
done

curl --silent --show-error --fail \
  -X POST "http://127.0.0.1:${port}/v1/audio/speech" \
  -H 'Content-Type: application/json' \
  -d '{"model":"kokoro","voice":"pf_dora(2)+af_bella(1)","input":"Oi. Eu sou a Hope. Você gostaria de ver seus saldos?","response_format":"mp3","speed":0.96}' \
  -o /dev/null

echo "Hope Velvet instalada e validada em http://127.0.0.1:${port}."
