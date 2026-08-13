---
name: HopeCash
description: Clareza financeira acolhedora, do registro cotidiano ao próximo passo.
colors:
  night: "#07111f"
  deep-blue: "#0d1b2a"
  navy: "#14273a"
  hope-green: "#0d7f57"
  hope-green-bright: "#3dd598"
  public-mint: "#57d6a1"
  paper: "#f5f8fa"
  white: "#ffffff"
  slate: "#52657a"
  line-light: "#dce5ec"
  line-dark: "#26394b"
  information-blue: "#1f5fe0"
  expense-red: "#b03a3a"
  warning-amber: "#a2600b"
  investment-purple: "#6b4cc9"
  focus-gold: "#f2bc62"
typography:
  display:
    fontFamily: "Bricolage Grotesque, Arial Narrow, sans-serif"
    fontSize: "clamp(3.1rem, 7vw, 6rem)"
    fontWeight: 720
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Bricolage Grotesque, Arial Narrow, sans-serif"
    fontSize: "clamp(2rem, 4vw, 4.5rem)"
    fontWeight: 710
    lineHeight: 1.04
    letterSpacing: "-0.035em"
  title:
    fontFamily: "Bricolage Grotesque, Arial Narrow, sans-serif"
    fontSize: "1.35rem"
    fontWeight: 700
    lineHeight: 1.26
    letterSpacing: "-0.02em"
  body:
    fontFamily: "Aptos, Segoe UI, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Aptos, Segoe UI, sans-serif"
    fontSize: "0.9rem"
    fontWeight: 680
    lineHeight: 1.2
  numeral:
    fontFamily: "Roboto, system-ui, sans-serif"
    fontSize: "2rem"
    fontWeight: 800
    lineHeight: 1.1
    letterSpacing: "-0.025em"
    fontFeature: "tabular-nums"
rounded:
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  pill: "999px"
spacing:
  xxs: "4px"
  xs: "8px"
  sm: "12px"
  md: "16px"
  lg: "20px"
  xl: "24px"
  xxl: "32px"
  xxxl: "40px"
components:
  button-primary:
    backgroundColor: "{colors.hope-green}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 20px"
    height: "48px"
  button-primary-dark-surface:
    backgroundColor: "{colors.public-mint}"
    textColor: "{colors.deep-blue}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 20px"
    height: "48px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.hope-green}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 20px"
    height: "48px"
  input:
    backgroundColor: "{colors.white}"
    textColor: "{colors.deep-blue}"
    typography: "{typography.body}"
    rounded: "{rounded.sm}"
    padding: "12px 16px"
    height: "50px"
  card:
    backgroundColor: "{colors.white}"
    textColor: "{colors.deep-blue}"
    rounded: "{rounded.md}"
    padding: "24px"
  chip-selected:
    backgroundColor: "#d9f0e5"
    textColor: "#063824"
    typography: "{typography.label}"
    rounded: "{rounded.pill}"
    padding: "6px 12px"
---

# Design System: HopeCash

## Overview

**Creative North Star: "Livro-razão da esperança"**

O HopeCash transforma informação financeira dispersa em uma leitura contínua, responsável e humana. A imagem do livro-razão aparece na disciplina do alinhamento, nas linhas que conectam nome e valor, nos pares de contexto e consequência e no modo como a interface primeiro explica a situação para só então oferecer uma ação. O verde-esperança funciona como sinal de progresso e controle; a base azul-petróleo dá gravidade sem tornar o produto frio.

O mundo alterna ambiente noturno e papel claro. O noturno concentra promessas, sínteses e momentos de orientação; o papel sustenta leitura, operação e conferência prolongadas. A densidade é moderada: informação suficiente para decisões reais, organizada por hierarquia, espaço e divisores em vez de pilhas indiferenciadas de cartões. A voz visual é clara, acolhedora e responsável, sem espetáculo financeiro ou promessas exageradas.

“Livro-razão” é uma gramática, não um molde de página. Linhas, colunas de números tabulares, listas e pares semânticos podem atravessar o app e as páginas públicas; índices de capítulos, tabelas de finalidade e a composição do painel de privacidade pertencem à estratégia da superfície que os usa.

**Key Characteristics:**

- Azul-petróleo profundo com papel claro e verde-esperança de alto contraste.
- Bricolage Grotesque editorial nas páginas públicas; tipografia de interface sóbria no produto.
- Ritmo espacial de 4 px, margens generosas e conteúdo agrupado por linhas e tonalidade.
- Números financeiros tabulares, alinhados e hierarquizados pela importância.
- Elevação rara: contorno e contraste tonal resolvem a maior parte da estrutura.
- Movimento breve, funcional e removido quando a pessoa prefere menos animação.

## Colors

A paleta combina a confiança do azul-petróleo, a possibilidade do verde e neutros de papel; cores semânticas só entram quando carregam significado financeiro ou estado.

### Primary

- **Verde-esperança** (`hope-green`): cor de ação, foco e progresso em superfícies claras; sua versão profunda preserva contraste com texto branco.
- **Verde-esperança luminoso** (`hope-green-bright`): variante de marca do app em tema escuro, com texto muito escuro por cima.
- **Menta pública** (`public-mint`): acento luminoso das superfícies públicas noturnas e de suas demonstrações.

### Secondary

- **Azul de informação** (`information-blue`): informação, investimento e estados de apoio; nunca substitui o verde como voz principal.

### Tertiary

- **Roxo de patrimônio** (`investment-purple`): cartões e investimento quando a distinção semântica é necessária.
- **Âmbar de atenção** (`warning-amber`): alertas e prazos que pedem atenção sem indicar erro.
- **Vermelho de saída** (`expense-red`): despesas, perdas e erro; não é decoração.

### Neutral

- **Noite** (`night`): pano de fundo público mais profundo e base do tema escuro.
- **Azul profundo** (`deep-blue`): tinta principal sobre papel e superfície elevada escura.
- **Azul-marinho** (`navy`): camada intermediária para separar planos escuros.
- **Papel** (`paper`): fundo público claro, levemente frio, para leitura longa.
- **Branco** (`white`): cartões e superfícies de máxima clareza.
- **Ardósia** (`slate`): texto secundário sobre papel, calibrado para permanecer legível.
- **Linha clara** (`line-light`) e **linha escura** (`line-dark`): divisores estruturais nos dois mundos.
- **Ouro de foco** (`focus-gold`): anel de foco visível em páginas públicas; não atua como acento decorativo.

### Named Rules

**The Two Greens Rule.** O verde de marca muda de luminância conforme a superfície; nunca force um único tom se isso reduzir o contraste.

**The Semantic Color Rule.** Azul, roxo, âmbar e vermelho só aparecem quando informam categoria, estado ou movimento financeiro.

**The Paper and Night Rule.** Papel acolhe leitura e operação; noite concentra síntese, promessa e orientação. A alternância deve esclarecer o modo, não decorar a rolagem.

## Typography

**Display Font:** Bricolage Grotesque (com Arial Narrow e sans-serif)

**Body Font:** Aptos (com Segoe UI e sans-serif) nas páginas públicas; a interface Flutter preserva a família nativa do Material.

**Label/Mono Font:** a família de interface, com números tabulares para valores financeiros.

**Character:** Bricolage dá voz editorial, compacta e otimista a títulos de comunicação. O corpo permanece familiar e silencioso para leitura e operação; dinheiro ganha alinhamento e estabilidade antes de ganhar personalidade.

### Hierarchy

- **Display** (peso 720, escala fluida, entrelinha 0,98): uma afirmação dominante por primeira viewport pública; tracking negativo mantém o bloco coeso.
- **Headline** (peso 710, escala fluida, entrelinha 1,04): abre seções e capítulos sem competir com o display.
- **Title** (peso 700, 1,35rem, entrelinha 1,26): nomeia grupos, linhas de livro-razão e unidades de decisão.
- **Body** (peso 400, 17px no desktop público, entrelinha 1,55): sustenta instruções e leitura longa; parágrafos densos ficam em torno de 62–72ch. No mobile público, o corpo recua para 16px.
- **Label** (peso 680, 0,9rem): navegação, metadados e controles; usa caixa normal, salvo vocabulário já estabelecido pelo componente.
- **Numeral** (peso 600–800 conforme ênfase): valores monetários sempre usam figuras tabulares; heróis, painéis, linhas e legendas seguem uma régua de importância.

### Named Rules

**The One Display Voice Rule.** Bricolage conduz títulos expressivos das páginas públicas; não migre a fonte display para todo texto operacional do app.

**The Stable Money Rule.** Valores de mesma função compartilham tamanho, peso, tracking e `tabular-nums`, para que colunas não “dancem” quando os números mudam.

## Layout

O app usa uma escala espacial em passos de 4 px, conteúdo máximo de 1120 px e padding lateral adaptativo. A navegação muda de barra inferior em larguras compactas para rail ou drawer em telas expandidas; o alvo mínimo próprio é 48×48 px/dp, mantendo também as garantias nativas de cada plataforma.

As páginas públicas usam contêiner de até 1180 px com 20 px de respiro por lado no desktop e 14 px no mobile. Desktop favorece assimetria controlada e no máximo duas colunas; abaixo de 900 px as composições principais tornam-se uma coluna, e abaixo de 640 px ações importantes ocupam a largura disponível. Conteúdo de leitura não deve se estender pela tela inteira.

O ritmo grande — 64 a 140 px entre capítulos públicos — separa mudanças de ideia. Dentro de uma unidade, use a escala pequena compartilhada: 4, 8, 12, 16, 20, 24, 32 e 40 px. Linhas de livro-razão podem substituir caixas quando nome, valor, finalidade ou estado já criam uma relação clara.

**The Responsive Recomposition Rule.** Responsividade reorganiza hierarquia e ordem; não apenas comprime colunas. Nenhuma superfície depende de rolagem horizontal.

## Elevation & Depth

O sistema é plano por padrão. Superfícies agrupadas usam contraste tonal e contorno de 1 px; elevação aparece quando o elemento é uma unidade independente de decisão, uma demonstração física ou um plano temporário. No app, cartões comuns têm elevação zero; nas páginas públicas, formulário, telefone e capturas recebem sombras ambientais suaves. Fundos escuros criam profundidade por camadas de azul, nunca por preto puro empilhado.

### Shadow Vocabulary

- **Demonstração ambiental** (`0 24px 70px rgba(2, 10, 20, 0.28)`): telefone e captura que precisam se separar do ambiente noturno.
- **Decisão sobre papel** (`0 24px 60px rgba(13, 27, 42, 0.08)`): formulário ou painel independente em superfície clara.
- **Ação verde** (`0 10px 26px rgba(13, 127, 87, 0.18)`): botão principal em papel; reforça ação sem simular volume físico.

### Named Rules

**The Flat-by-Default Rule.** Se borda, espaçamento ou tom já explicam o agrupamento, não adicione sombra.

**The Decision Earns Elevation Rule.** Apenas uma unidade independente de decisão, foco ou demonstração pode subir do plano.

## Shapes

O HopeCash usa cantos suavemente curvos e consistentes. Controles e botões usam 12 px; cartões usam 16 px; contêineres maiores e modais podem chegar a 20–24 px. O raio de 8 px fica reservado a controles compactos, tooltips e ações de baixo peso. Pílulas de 999 px pertencem a chips, indicadores e seleções, não a todo retângulo.

Linhas de 1 px são parte ativa da forma: dividem registros, capítulos e estados sem criar novas caixas. Círculos pequenos funcionam como marcadores semânticos; molduras de dispositivo podem exceder a escala de raios porque representam um objeto físico. Balões de conversa podem quebrar um único canto para indicar autoria.

**The Gentle Geometry Rule.** Curvas devem acolher sem infantilizar: use a escala de raios existente e preserve linhas retas onde a leitura tabular pede precisão.

## Components

### Buttons

- **Shape:** retângulo suavemente curvo (12 px), altura mínima de 48 px e peso de rótulo forte.
- **Primary:** verde profundo com texto branco sobre papel; menta luminosa com texto azul profundo sobre noite; padding horizontal de 20 px nas páginas públicas.
- **Hover / Focus:** sobe apenas 2 px no hover público e retorna no active; foco usa anel de 3 px com afastamento de 4 px. O app usa os estados nativos do Material 3.
- **Secondary / Ghost:** fundo transparente e contorno da cor corrente; em superfícies escuras recebe uma névoa verde discreta no hover.

### Chips

- **Style:** forma de pílula, contorno sutil e rótulo de interface. O estado selecionado usa superfície verde suave com tinta verde-azulada escura.
- **State:** a cor indica seleção, não categoria decorativa; checkmark e texto devem compartilhar o mesmo contraste.

### Cards / Containers

- **Corner Style:** 16 px para cartões comuns; 20–24 px para contêineres de maior escala.
- **Background:** branco no tema claro, azul elevado no tema escuro e tons semânticos suaves somente quando o conteúdo os justifica.
- **Shadow Strategy:** plano com contorno por padrão; consulte `Elevation & Depth` para exceções.
- **Border:** 1 px no token de linha ou contorno suave do tema.
- **Internal Padding:** 16–24 px para unidades comuns; 32–40 px apenas em painéis espaçosos.

### Inputs / Fields

- **Style:** fundo branco ou quase branco, borda de 1 px, raio de 12 px, altura mínima de 50 px nas páginas públicas.
- **Focus:** borda verde e anel translúcido na Web; borda de 2 px no tema Flutter. Nunca dependa apenas da cor: o foco global permanece visível.
- **Error / Disabled:** erro usa vermelho semântico com texto explicativo; desabilitado reduz contraste, mas conserva rótulo legível e estrutura.

### Navigation

A navegação pública é horizontal, leve e sem sombra, com marca à esquerda e ação principal à direita; links secundários desaparecem no mobile antes que a barra fique apertada. No app, use barra inferior para larguras compactas e rail/drawer em telas maiores, com indicador tonal em forma de pílula e rótulos sempre visíveis quando o componente os prevê.

### Ledger Rows

Linhas de livro-razão apresentam um termo forte e uma explicação, valor ou limite secundário, separados por divisores em vez de cartões. Em telas estreitas, as colunas empilham e preservam a ordem semântica. Use esse padrão para relações comparáveis e escaneáveis; ele não obriga toda página a adotar uma tabela ou índice.

### Hope Conversation

Mensagens usam superfícies contrastantes, sombra ambiental e um único canto reduzido para autoria. A fala da pessoa tende ao azul informativo; a Hope usa verde-papel com tinta escura. O padrão representa conversa real ou demonstração do recurso, nunca decoração abstrata.

## Do's and Don'ts

### Do:

- **Do** mostre a situação financeira com hierarquia clara antes de pedir ação.
- **Do** use papel e noite para distinguir modos de leitura, síntese e orientação.
- **Do** alinhe números com figuras tabulares e mantenha valores comparáveis na mesma régua tipográfica.
- **Do** prefira linhas, espaço e contraste tonal para agrupar informações relacionadas.
- **Do** preserve foco visível, alvos confortáveis, contraste, redução de movimento e recomposição responsiva.
- **Do** mantenha a composição própria de cada superfície no respectivo brief; reutilize a gramática, não o molde.

### Don't:

- **Don't** transforme cada capacidade, capítulo ou dado em um cartão repetitivo.
- **Don't** use cores semânticas como decoração ou um único verde sobre fundos incompatíveis.
- **Don't** espalhe Bricolage por texto operacional longo ou números densos do app.
- **Don't** aplique sombra quando borda, alinhamento ou tom já explicam a hierarquia.
- **Don't** invente métricas, preços, depoimentos ou promessas financeiras para preencher composição.
- **Don't** transforme o painel de privacidade, seu índice ou sua tabela finalidade/limite em regra global do HopeCash.
