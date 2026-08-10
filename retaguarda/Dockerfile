# Versao fixa (nao usar :stable) — a tag movel troca de digest e forca o
# re-download da camada do SDK Flutter (~330MB) a cada deploy. Alinhada ao app.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

WORKDIR /app
ARG API_BASE_URL=http://localhost:3000
ARG BUILD_REF=local
ARG BUILD_TIME=

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
# APP_VERSION vem do pubspec (fonte unica); BUILD_REF/BUILD_TIME vem do deploy.
RUN APP_VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)" && \
    flutter build web --release \
      --dart-define=API_BASE_URL=${API_BASE_URL} \
      --dart-define=APP_VERSION=${APP_VERSION} \
      --dart-define=BUILD_REF=${BUILD_REF} \
      --dart-define=BUILD_TIME=${BUILD_TIME}

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

# SPA Flutter: index e artefatos de bootstrap sem cache; fontes com cache longo.
RUN printf 'server {\n\
  listen 80;\n\
  root /usr/share/nginx/html;\n\
  index index.html;\n\
\n\
  location = / {\n\
    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;\n\
    try_files /index.html =404;\n\
  }\n\
\n\
  location = /index.html {\n\
    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;\n\
    try_files $uri =404;\n\
  }\n\
\n\
  location ~ ^/(flutter_bootstrap\\.js|flutter_service_worker\\.js|main\\.dart\\.js|version\\.json|manifest\\.json)$ {\n\
    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;\n\
    try_files $uri =404;\n\
  }\n\
\n\
  location ~* \\.ttf$ {\n\
    types { font/ttf ttf; }\n\
    add_header Cache-Control "public, max-age=31536000, immutable" always;\n\
    try_files $uri =404;\n\
  }\n\
\n\
  location / {\n\
    add_header Cache-Control "no-store, no-cache, must-revalidate, proxy-revalidate, max-age=0" always;\n\
    try_files $uri $uri/ /index.html;\n\
  }\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
