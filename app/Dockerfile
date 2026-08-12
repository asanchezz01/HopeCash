# A Cirrus ainda nao publica a imagem 3.44.1. Usamos a imagem fixa 3.44.0 como
# base e avancamos o SDK para o commit exato do Flutter 3.44.1 validado no
# Chrome desktop. Essa atualizacao inclui o engine c416acfe, que corrige a
# apresentacao inicial da superficie em janela maximizada.
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS build

ARG FLUTTER_VERSION=3.44.1
ARG FLUTTER_REVISION=924134a44c189315be2148659913dda1671cbe99
RUN git -C "$FLUTTER_ROOT" fetch --depth 1 origin \
      "refs/tags/${FLUTTER_VERSION}:refs/tags/${FLUTTER_VERSION}" && \
    git -C "$FLUTTER_ROOT" checkout --detach "$FLUTTER_REVISION" && \
    test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_REVISION" && \
    flutter precache --web

WORKDIR /app
ARG API_BASE_URL=http://localhost:3000
ARG BUILD_REF=local
ARG BUILD_TIME=
# Notificacoes push (Firebase Cloud Messaging) — Web/PWA. Chaves publicas do
# app Web ja registrado no Firebase; sem valor padrao (build sem elas sobe
# normalmente, so sem push no navegador). Ver docs/FLUTTERFIRE.md.
ARG FIREBASE_PROJECT_ID=hopecash
ARG FIREBASE_MESSAGING_SENDER_ID=71481307234
ARG FIREBASE_WEB_APP_ID=1:71481307234:web:c284cb740f37342f9a613b
ARG FIREBASE_STORAGE_BUCKET=hopecash.firebasestorage.app
ARG FIREBASE_WEB_AUTH_DOMAIN=hopecash.firebaseapp.com
ARG FIREBASE_WEB_API_KEY=
ARG FIREBASE_VAPID_KEY=

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
# APP_VERSION vem do pubspec (fonte unica); BUILD_REF/BUILD_TIME vem do deploy.
RUN APP_VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/version:[[:space:]]*//' | cut -d'+' -f1)" && \
    dart run build_runner build && \
    flutter build web --release \
      --dart-define=API_BASE_URL=${API_BASE_URL} \
      --dart-define=APP_VERSION=${APP_VERSION} \
      --dart-define=BUILD_REF=${BUILD_REF} \
      --dart-define=BUILD_TIME=${BUILD_TIME} \
      --dart-define=FIREBASE_PROJECT_ID=${FIREBASE_PROJECT_ID} \
      --dart-define=FIREBASE_MESSAGING_SENDER_ID=${FIREBASE_MESSAGING_SENDER_ID} \
      --dart-define=FIREBASE_WEB_APP_ID=${FIREBASE_WEB_APP_ID} \
      --dart-define=FIREBASE_STORAGE_BUCKET=${FIREBASE_STORAGE_BUCKET} \
      --dart-define=FIREBASE_WEB_AUTH_DOMAIN=${FIREBASE_WEB_AUTH_DOMAIN} \
      --dart-define=FIREBASE_WEB_API_KEY=${FIREBASE_WEB_API_KEY} \
      --dart-define=FIREBASE_VAPID_KEY=${FIREBASE_VAPID_KEY}

# O service worker do FCM e um arquivo estatico (nao passa pelo compilador
# Dart) — os mesmos valores viram placeholders substituidos aqui.
RUN sed -i \
      -e "s|__FIREBASE_WEB_API_KEY__|${FIREBASE_WEB_API_KEY}|g" \
      -e "s|__FIREBASE_WEB_AUTH_DOMAIN__|${FIREBASE_WEB_AUTH_DOMAIN}|g" \
      -e "s|__FIREBASE_PROJECT_ID__|${FIREBASE_PROJECT_ID}|g" \
      -e "s|__FIREBASE_STORAGE_BUCKET__|${FIREBASE_STORAGE_BUCKET}|g" \
      -e "s|__FIREBASE_MESSAGING_SENDER_ID__|${FIREBASE_MESSAGING_SENDER_ID}|g" \
      -e "s|__FIREBASE_WEB_APP_ID__|${FIREBASE_WEB_APP_ID}|g" \
      build/web/firebase-messaging-sw.js

# A página pública de suporte usa a mesma API compilada no app, sem manter uma
# segunda URL fixa em JavaScript.
RUN sed -i "s|__API_BASE_URL__|${API_BASE_URL}|g" build/web/public/support.js

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html

# Cabeçalhos exigidos pelo SQLite WASM (drift) para usar OPFS/SharedArrayBuffer.
RUN printf 'server {\n\
  listen 80;\n\
  root /usr/share/nginx/html;\n\
  index index.html;\n\
  add_header Cross-Origin-Opener-Policy same-origin always;\n\
  add_header Cross-Origin-Embedder-Policy require-corp always;\n\
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
  location ~ ^/(flutter_bootstrap\\.js|flutter_service_worker\\.js|firebase-messaging-sw\\.js|main\\.dart\\.js|version\\.json|manifest\\.json)$ {\n\
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
