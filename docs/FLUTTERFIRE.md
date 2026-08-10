# Notificações push — configuração Firebase/FlutterFire

Projeto Firebase único, já criado e configurado no Console — **nunca crie outro app ou outro par de chaves**; esta página só documenta como reaproveitar o que já existe.

| Item | Valor |
|---|---|
| Projeto | `HopeCash` |
| Project ID | `hopecash` |
| Project Number / FCM Sender ID | `71481307234` |
| Cloud Messaging | HTTP v1 ativado; API legada desativada (esperado) |
| App Android | `HopeCash Android` · `br.com.newhope.hopecash` · `1:71481307234:android:66495a59ef0417739a613b` |
| App iOS | `HopeCash iOS` · `br.com.newhope.hopecash` · `1:71481307234:ios:10834ab1bc00ed069a613b` |
| App Web/PWA | `HopeCash Web/PWA` · `1:71481307234:web:c284cb740f37342f9a613b` |

## 1. Backend (Firebase Admin SDK)

O backend usa `firebase-admin` (`backend/src/modules/push/firebaseAdmin.js`) inicializado a partir de variáveis de ambiente — nunca de um arquivo de credencial em disco em tempo de execução.

```dotenv
FIREBASE_ENABLED=true
FIREBASE_PROJECT_ID=hopecash
FIREBASE_CLIENT_EMAIL=firebase-adminsdk-xxxxx@hopecash.iam.gserviceaccount.com
FIREBASE_PRIVATE_KEY_BASE64=<campo "private_key" da credencial, em Base64 UTF-8>
```

- `FIREBASE_PRIVATE_KEY_BASE64` é **só** o campo `private_key` do JSON da credencial (não o JSON inteiro), codificado em Base64. O backend decodifica com `Buffer.from(valor, 'base64').toString('utf8')` e valida que o resultado é um PEM (`-----BEGIN PRIVATE KEY-----`) antes de usar — nunca loga o conteúdo.
- `FIREBASE_ENABLED=false` (padrão em `.env.example`) faz o backend subir normalmente com um provedor *dry-run* (`DisabledPushProvider`) — nada é enviado, mas nenhuma rota quebra.
- Em produção, `FIREBASE_ENABLED=true` com configuração ausente/inválida **derruba o processo de propósito** (falha clara no boot, não silenciosa). Fora de produção, apenas loga o erro e segue em dry-run.
- Testes automatizados **nunca** tocam o Firebase real: `NODE_ENV=test` sempre usa `FakePushProvider` (ver `backend/src/modules/push/providers/`), independentemente do valor de `FIREBASE_ENABLED`.

### Rotação da credencial administrativa

A cópia local protegida fica em `secret/hopecash-firebase-admin.json` (fora do Git — `secret/` está no `.gitignore` da raiz; `backend/.gitignore` também bloqueia `*-firebase-adminsdk-*.json` e `service-account*.json`). Para rotacionar:

1. No Firebase Console: **Configurações do projeto → Contas de serviço → Gerar nova chave privada**.
2. Salve o novo JSON em `secret/hopecash-firebase-admin.json` (sobrescrevendo o anterior) — só como cópia de referência, nunca lido pelo backend em runtime.
3. Extraia o campo `private_key`, converta para Base64 UTF-8 e atualize `FIREBASE_PRIVATE_KEY_BASE64` (e `FIREBASE_CLIENT_EMAIL`, se o e-mail da conta de serviço mudou) no `.env` do servidor (`/opt/hopecash/.env` — ver [DEPLOY.md](DEPLOY.md)).
4. Redeploy da API. A credencial antiga pode ser revogada no Console depois de confirmar que o novo deploy está enviando push com sucesso.
5. Revogue/exclua a chave antiga no Console (Contas de serviço) para não deixar duas chaves válidas.

## 2. Android

Já finalizado no código:

- `app/android/app/google-services.json` — arquivo real do Firebase, já no lugar certo (`project_id=hopecash`, `package_name=br.com.newhope.hopecash`).
- Plugin do Google Services aplicado (`android/settings.gradle.kts` + `android/app/build.gradle.kts`).
- `AndroidManifest.xml`: permissão `POST_NOTIFICATIONS` (Android 13+) e `meta-data` de canal/ícone/cor padrão (`hopecash_default`, cor `#16C784` em `res/values/colors.xml`).
- Não interfere com `BankNotificationListenerService` (captura de notificações bancárias) — são canais e plugins completamente independentes.

Nada manual a fazer aqui além de compilar (`flutter build apk`/`appbundle`).

## 3. iOS

Já finalizado no código:

- `app/ios/Runner/GoogleService-Info.plist` — arquivo real do Firebase, referenciado no projeto Xcode (fase de Resources do target `Runner`).
- `Info.plist`: `UIBackgroundModes` inclui `remote-notification`.
- `Firebase.initializeApp()` (chamado a partir do Dart, em `PushNotificationsService.initialize`) configura o SDK nativo automaticamente a partir do `GoogleService-Info.plist` — não precisa de código Swift adicional no `AppDelegate` (o Firebase faz *method swizzling* para receber o token APNs e as notificações remotas).

### Pendência externa: APNs

**Isto não pode ser resolvido em código** — depende de acesso à conta Apple Developer. Falta cadastrar no Firebase Console (**Configurações do projeto → Cloud Messaging → Configuração do app Apple**) uma das duas opções:

- **Chave de autenticação APNs** (`.p8`) — recomendado, não expira: arquivo `.p8` + Key ID + Apple Team ID (obtidos em [developer.apple.com](https://developer.apple.com) → Certificates, Identifiers & Profiles → Keys); ou
- **Certificado APNs** (`.p12`) por ambiente (desenvolvimento/produção) — expira anualmente.

Enquanto isso não for feito, o app iOS compila e roda normalmente, o token FCM é obtido, mas o push **não chega** nos dispositivos iOS (as demais plataformas — Android, Web, PWA — funcionam independentemente disso).

## 4. Web / PWA

Não existe arquivo de configuração nativo para Web — os valores públicos do app `HopeCash Web/PWA` são passados no build via `--dart-define`, exatamente como `API_BASE_URL` já é hoje:

| `--dart-define` | Origem | Segredo? |
|---|---|---|
| `FIREBASE_PROJECT_ID` | `hopecash` (fixo) | Não |
| `FIREBASE_MESSAGING_SENDER_ID` | `71481307234` (fixo) | Não |
| `FIREBASE_WEB_APP_ID` | `1:71481307234:web:c284cb740f37342f9a613b` (fixo) | Não |
| `FIREBASE_STORAGE_BUCKET` | `hopecash.firebasestorage.app` (fixo) | Não |
| `FIREBASE_WEB_AUTH_DOMAIN` | `hopecash.firebaseapp.com` (convenção padrão) | Não |
| `FIREBASE_WEB_API_KEY` | **Firebase Console → Configurações do projeto → Geral → seus apps → Web `HopeCash Web/PWA`** → trecho de configuração (`apiKey`) | Não é segredo (chave pública do Firebase), mas ainda não preenchido neste repositório |
| `FIREBASE_VAPID_KEY` | **Firebase Console → Configurações do projeto → Cloud Messaging → Configuração da Web → Certificados push da Web** (par já existente) | Não é segredo, mas ainda não preenchido |

Sem esses dois últimos valores, o push no navegador simplesmente fica desabilitado (`AppConfig.firebaseWebConfigured == false`) — Web/PWA continuam funcionando normalmente (offline-first, instalação da PWA, etc.), só sem notificações push.

### Onde esses valores entram no build

1. `app/lib/core/config/app_config.dart` — `String.fromEnvironment(...)`, mesmo padrão de `apiBaseUrl`.
2. `app/Dockerfile` — `ARG`s repassados como `--dart-define` para o `flutter build web`.
3. `docker-compose.yml` (raiz) — `args:` do serviço `web`.
4. `scripts/deploy.sh` — preserva os valores do `.env` persistente do servidor entre deploys (mesmo mecanismo de `MAIL_USER`/`MAIL_PASS` hoje).

Para ativar o push no navegador em produção: adicione `FIREBASE_WEB_API_KEY` e `FIREBASE_VAPID_KEY` ao `.env` do servidor (`/opt/hopecash/.env`) e rode o deploy novamente.

### Service worker (`firebase-messaging-sw.js`)

`app/web/firebase-messaging-sw.js` é um arquivo estático (não passa pelo compilador Dart) com placeholders (`__FIREBASE_WEB_API_KEY__` etc.) substituídos em build time pelo `Dockerfile` (`sed`), usando os mesmos valores acima. Ele é registrado automaticamente pelo plugin `firebase_messaging` num escopo próprio (`/firebase-cloud-messaging-push-scope`), **sem conflito** com:

- `flutter_service_worker.js` — cache offline-first gerado pelo Flutter;
- `drift_worker.js` — SQLite WASM (banco local).

## 5. Testando sem atingir usuários reais

1. **Testes automatizados**: rodam sempre com `FakePushProvider` (backend) — nunca fazem uma chamada real ao FCM. `npm test` em `backend/` cobre inicialização habilitada/desabilitada, registro de dispositivo, preferências, campanhas (CRUD, envio, agendamento, cancelamento, reprocessamento), avisos de vencimento (idempotência, fuso, preferências) e retry/backoff (falha permanente × temporária, concorrência entre instâncias do worker).
2. **Teste manual controlado**: na retaguarda, crie uma campanha com **audiência "Selecionados"** e escolha só a sua própria conta de teste (nunca "Todos os usuários" para validar algo). Registre um dispositivo de teste (`POST /push/devices` a partir do app rodando localmente) e confirme o recebimento antes de qualquer envio amplo.
3. **Ambiente local sem Firebase real**: deixe `FIREBASE_ENABLED=false` no `.env` local — a API funciona normalmente (dry-run) e você pode testar todo o fluxo de campanhas/preferências/estatísticas na retaguarda sem que nenhum push seja realmente disparado.
4. **Nunca** use `FIREBASE_ENABLED=true` com as credenciais reais apontando para o mesmo projeto usado em produção a partir de um ambiente de desenvolvimento compartilhado, para não arriscar notificar usuários reais por engano.
