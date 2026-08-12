---
name: HopeCash
description: Clareza financeira que conecta dados, planos e conversa.
colors:
  night: "#07111f"
  night-raised: "#0d1b2a"
  navy: "#14273a"
  hope-mint: "#57d6a1"
  hope-mint-deep: "#0d7f57"
  sky: "#8db2ff"
  lilac: "#b8a7ff"
  rose: "#ff9e9e"
  gold: "#f2bc62"
  paper: "#f5f8fa"
  white: "#ffffff"
  slate: "#52657a"
  line-dark: "#26394b"
  line-light: "#dce5ec"
typography:
  display:
    fontFamily: "Bricolage Grotesque, Arial Narrow, sans-serif"
    fontSize: "clamp(3.4rem, 7.1vw, 6rem)"
    fontWeight: 720
    lineHeight: 0.98
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Bricolage Grotesque, Arial Narrow, sans-serif"
    fontSize: "clamp(2.3rem, 5vw, 4.5rem)"
    fontWeight: 710
    lineHeight: 1.02
    letterSpacing: "-0.035em"
  body:
    fontFamily: "Aptos, Segoe UI, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.55
  label:
    fontFamily: "Aptos, Segoe UI, sans-serif"
    fontSize: "0.94rem"
    fontWeight: 650
    lineHeight: 1
rounded:
  sm: "12px"
  md: "16px"
  lg: "24px"
  phone: "38px"
  pill: "999px"
components:
  button-primary:
    backgroundColor: "{colors.hope-mint}"
    textColor: "#04231a"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 20px"
    height: "48px"
  button-support:
    backgroundColor: "{colors.hope-mint-deep}"
    textColor: "{colors.white}"
    typography: "{typography.label}"
    rounded: "{rounded.sm}"
    padding: "0 20px"
    height: "48px"
  input:
    backgroundColor: "#fbfcfd"
    textColor: "{colors.night-raised}"
    rounded: "{rounded.sm}"
    padding: "0 14px"
    height: "50px"
---

# Design System: HopeCash

## Overview

**Creative North Star: "O Caminho Financeiro Conversacional"**

O HopeCash transforma informações financeiras dispersas em um percurso legível: ver, entender, planejar e agir. O sistema combina um ambiente noturno concentrado com superfícies claras de resolução, usando verde-esperança como sinal de progresso e controle — nunca como promessa de resultado financeiro.

A identidade é tecnológica sem ser fria. Tipografia expressiva dá voz às grandes ideias; texto funcional, telas reais e mensagens diretas sustentam a confiança. Composições podem ser assimétricas, mas a leitura sempre segue um caminho evidente e responsável.

**Key Characteristics:**

- contraste entre azul-petróleo profundo e papel claro;
- verde-esperança reservado para ações, progresso e ênfase;
- títulos compactos e expressivos combinados a corpo calmo;
- evidência do produto por dados e telas reais, não por promessas abstratas;
- profundidade ambiental, foco visível e movimento discreto.

## Colors

A paleta alterna concentração noturna e clareza editorial, com acentos suaves que distinguem informação sem transformar a experiência em um painel multicolorido.

### Primary

- **Azul-petróleo noturno:** fundo imersivo de marketing e base de maior contraste.
- **Verde-esperança:** ações principais, ênfase positiva e conexão visual com a marca.
- **Verde-esperança profundo:** ação sobre superfícies claras e estados que exigem contraste reforçado.

### Secondary

- **Céu e lilás suaves:** profundidade ambiental e detalhes de visualização, sempre em baixa presença.
- **Rosa e ouro:** sinais semânticos pontuais para despesas, alertas ou categorias; não competem com a ação primária.

### Neutral

- **Papel frio e branco:** leitura longa, suporte e campos.
- **Ardósia:** texto secundário sobre superfícies claras.
- **Linhas clara e escura:** divisores discretos que organizam sem formar caixas em excesso.

**The Hope Signal Rule.** O verde é um sinal raro e funcional: ação, progresso ou palavra-chave. Grandes áreas verdes só aparecem quando a própria superfície é a mensagem.

## Typography

**Display Font:** Bricolage Grotesque (com Arial Narrow e sans-serif como fallback)  
**Body Font:** Aptos (com Segoe UI e sans-serif como fallback)

**Character:** Bricolage dá personalidade humana e compacta aos títulos; Aptos mantém formulários, explicações e dados familiares e fáceis de percorrer.

### Hierarchy

- **Display:** peso variável forte, altura de linha muito compacta e tracking negativo; reservado a uma promessa principal por superfície.
- **Headline:** escala fluida e compacta para abrir seções e organizar a narrativa.
- **Body:** 17px no desktop e 16px no mobile, altura de linha 1.55; parágrafos explicativos ficam em torno de 58–62 caracteres.
- **Label:** 0.92–0.94rem, peso 650–720; controles e navegação usam caixa normal, não texto integralmente em maiúsculas.

**The One Loud Sentence Rule.** Uma viewport recebe um único título dominante; os demais níveis orientam, não disputam atenção.

## Layout

O container principal tem largura máxima de 1180px e margens laterais de 20px; abaixo de 640px, as margens passam a 14px. Desktop favorece pares assimétricos e gaps fluidos. Em 900px, grids principais viram uma coluna; em 640px, ações passam a ocupar a largura disponível, formulários deixam de ter colunas paralelas e a navegação oculta links secundários.

O ritmo usa áreas amplas entre capítulos e espaçamento compacto dentro de um mesmo assunto. Telas e mensagens podem se sobrepor para demonstrar conexão, desde que o fluxo de leitura e o conteúdo permaneçam intactos em 320px ou mais. Overflow horizontal nunca é parte da composição.

## Elevation & Depth

O sistema usa um híbrido: superfícies editoriais são planas e separadas por tom ou linha; dispositivos, mensagens e o formulário de suporte recebem sombras ambientais para indicar objetos importantes. Anéis grandes e translúcidos podem criar profundidade no fundo, sem virar ornamento dominante.

### Shadow Vocabulary

- **Objeto elevado:** sombra ampla e escura para mockups e capturas que flutuam sobre o ambiente noturno.
- **Mensagem:** sombra média para separar balões sobre telas reais.
- **Ação:** brilho verde baixo sob botões primários.
- **Papel suspenso:** sombra azul-petróleo muito suave no formulário sobre fundo claro.

**The Evidence Floats Rule.** Elevação destaca evidência ou ação; conteúdo editorial comum permanece plano.

## Shapes

Controles usam cantos gentilmente arredondados. Botões e campos compartilham raio pequeno; painéis usam raio médio ou grande. Molduras de dispositivos podem ter silhueta muito mais arredondada, enquanto divisores permanecem finos. Balões de conversa usam um canto reduzido para indicar direção, sem recorrer a caudas ilustrativas.

## Components

### Buttons

- **Shape:** retângulo arredondado de 12px, altura mínima de 48px; 44px é o mínimo mobile na navegação.
- **Primary:** verde-esperança com texto azul-esverdeado escuro; em superfícies claras, verde profundo com texto branco.
- **Hover / Focus:** leve elevação de 2px e mudança de tom; foco global em anel ouro de 3px com afastamento de 4px.
- **Secondary:** fundo transparente, borda na cor do texto e ausência de sombra.

### Cards / Containers

- **Corner Style:** 16px para formulário e superfícies editoriais; 24px quando uma seção precisa de presença maior.
- **Background:** branco ou tom elevado do ambiente noturno.
- **Shadow Strategy:** somente quando o container representa objeto, diálogo ou ponto de ação.
- **Border:** linha clara no suporte; linha escura ou translúcida no ambiente noturno.

### Inputs / Fields

- **Style:** fundo quase branco, borda cinza-azulada de 1px, raio de 12px e altura mínima de 50px.
- **Focus:** borda verde profunda e anel verde translúcido de 3px.
- **Hints / Status:** ardósia para ajuda; verde profundo para sucesso e vermelho escuro para erro, acompanhados por texto sem depender apenas da cor.

### Navigation

Cabeçalho de 76px no desktop e 68px no mobile, com marca à esquerda e ação principal à direita. Marketing usa fundo noturno translúcido; suporte usa papel translúcido. Abaixo de 640px, links contextuais somem e a ação permanece.

### Conversation Thread

Balões curtos demonstram uma pergunta e uma resposta conectada a uma tela real. Usuário usa azul profundo; Hope usa papel esverdeado. O conteúdo deve explicar comportamento confirmado e nunca simular aconselhamento ou resultado financeiro garantido.

## Do's and Don'ts

### Do:

- **Do** use telas reais e linguagem direta para provar uma capacidade.
- **Do** preserve foco visível, alvos de toque confortáveis e estados comunicados por texto.
- **Do** use assimetria para conduzir a leitura e sequência linear em telas estreitas.
- **Do** respeite `prefers-reduced-motion` e mantenha todo conteúdo acessível sem JavaScript.

### Don't:

- **Don't** invente métricas, depoimentos, preços ou promessas de ganho.
- **Don't** transforme recursos em grades repetitivas de cartões sem narrativa.
- **Don't** use o verde como preenchimento decorativo indiscriminado.
- **Don't** deixe mockups, rotações ou sobreposições criarem rolagem horizontal.
- **Don't** solicite senhas, tokens ou dados financeiros sensíveis em formulários de suporte.
