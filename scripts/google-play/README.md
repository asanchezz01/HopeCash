# Recursos gráficos para o Google Play

Gera um pacote pronto para a página padrão do HopeCash no Google Play Console usando capturas reais do app.

## Gerar

```powershell
python scripts/google-play/generate-assets.py
```

Saída: `store-assets/google-play/`

## Conteúdo

- `icon-512.png`: ícone 512 × 512 px, PNG, sem cantos pré-recortados.
- `feature-graphic-1024x500.png`: recurso gráfico 1024 × 500 px.
- `phone/`: oito imagens 1080 × 1920 px (9:16).
- `tablet-7/`: oito imagens 1920 × 1080 px (16:9).
- `tablet-10/`: oito imagens 1920 × 1080 px (16:9).
- `manifest.json`: dimensões, tamanho e SHA-256 de cada arquivo.

Os requisitos foram conferidos na página “Detalhes do app” do Play Console em 14/08/2026. Chromebook e Android XR não são campos obrigatórios para esta ficha e não fazem parte do pacote.

O fundo abstrato do recurso gráfico foi criado com geração de imagem; tipografia, logotipo e capturas foram aplicados deterministicamente pelo script para preservar os textos e a interface reais.
