// Service worker do Firebase Cloud Messaging para Web/PWA — completamente
// separado do service worker gerado pelo Flutter (flutter_service_worker.js,
// que cuida do cache offline-first) e do drift_worker.js (SQLite WASM). O
// plugin firebase_messaging registra este arquivo automaticamente pelo nome
// fixo "firebase-messaging-sw.js" na raiz do site.
//
// Os placeholders abaixo (__FIREBASE_..._) são substituídos em build time
// (ver Dockerfile) pelos mesmos valores injetados via --dart-define no app.
// Não são segredo — chaves Web do Firebase são públicas por design (a
// segurança vem das regras do projeto/App Check, não do sigilo da chave).
importScripts('https://www.gstatic.com/firebasejs/12.16.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.16.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: '__FIREBASE_WEB_API_KEY__',
  authDomain: '__FIREBASE_WEB_AUTH_DOMAIN__',
  projectId: '__FIREBASE_PROJECT_ID__',
  storageBucket: '__FIREBASE_STORAGE_BUCKET__',
  messagingSenderId: '__FIREBASE_MESSAGING_SENDER_ID__',
  appId: '__FIREBASE_WEB_APP_ID__',
});

// Mensagens com bloco "notification" já são exibidas automaticamente pelo
// navegador com o app em segundo plano — nada a fazer aqui além de registrar
// o handler exigido pelo SDK.
firebase.messaging().onBackgroundMessage(() => {});
