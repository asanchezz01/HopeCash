{{flutter_js}}
{{flutter_build_config}}

// Usa a variante completa do CanvasKit em modo CPU. Alguns drivers de desktop
// criam a superficie WebGL maximizada, mas nao apresentam o primeiro frame ate
// uma mudanca real no viewport. O HopeCash nao depende de graficos 3D, entao o
// renderer por CPU evita a tela preta sem afetar as funcionalidades do app.
const engineConfig = {
  renderer: 'canvaskit',
  canvasKitBaseUrl: 'canvaskit/',
  canvasKitVariant: 'full',
  canvasKitForceCpuOnly: true,
};

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
  config: engineConfig,
});
