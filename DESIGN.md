# DESIGN.md — Éde Gestão

> Sistema de design do **app** (modo **Operate**), derivado do manual da marca da Éde Utilidades
> ([manual da marca](https://claude.ai/artifact/YGoYHxstwQUUx9PJYAH2KR)). O **porquê** e o **para
> quem** estão em `PRODUCT.md`; decisões em `docs/decisoes.md` (D110–D119).
>
> **Fonte única dos valores:** `src/lib/design/tokens.ts`. O CSS (`src/app/tokens.css`) e as
> tabelas no fim deste arquivo são **gerados** por `pnpm tokens`. O `pnpm test` falha se o CSS ou
> as tabelas estiverem desatualizados (`tokens-sync.test.ts`) ou se algum par de cores declarado
> não passar AA nos dois temas (`contrast.test.ts`).
>
> **Catálogo vivo:** `/prototipo/componentes` (com `ENABLE_PROTOTYPES=1`, ver `docs/dev-local.md`).

## 1. Princípios

O app é usado em pé, no corredor da loja, com uma mão ocupada, luz forte, pressa e internet ruim.

1. **Escaneável antes de bonito.** Status, horário e o que fazer agora aparecem primeiro.
2. **A marca vive nos detalhes precisos:** o laranja na ação principal e no logo, Bitter nos
   títulos e números, creme e areia nas superfícies. Nada de decoração.
3. **Menos motion.** O que se vê 100 vezes por dia não anima.
4. **Estado completo em toda tela:** carregando (esqueleto), vazio (com orientação), erro (com ação)
   e sem conexão.
5. **Cor nunca decide sozinha.** Status = cor + ícone + texto.

Proibido no app: gradiente decorativo, glassmorphism, cartões idênticos com ícone no topo, emoji,
sombra em elemento em repouso, rótulo minúsculo em caixa-alta espaçada (o estilo `etiqueta` do
manual não entra no app), spinner de página inteira, animação de entrada em gráfico.

## 2. A marca no app

| Do manual | No app |
| --- | --- |
| Logo horizontal (`ede-horizontal-*`) | Cabeçalho das áreas logadas e 404, `laranja` nos dois temas (o manual permite laranja sobre creme e sobre cacau). Mínimo 150px. Área de proteção livre (nada de texto colado). |
| Logo principal (`ede-principal-*`) | Painel laranja das páginas públicas, versão `branco` (manual: sobre laranja, logo branco). |
| Ícone (`ede-icone-app`) | Favicon / ícone do app (`src/app/icon.svg`). |
| Padrão de casas | Só no painel laranja das páginas públicas, numa faixa sem texto pequeno e fora da área de proteção do logo. |
| `laranja-ede` | Logo, painel das páginas públicas, botão primário no tema escuro. Texto branco sobre ele só a partir de 24px (ou negrito de 19px). |
| `laranja-brasa` | Botão primário no tema claro (texto branco, 5,00:1), anel de foco, caixa marcada do checklist. |
| `cacau` / `cacau-suave` | Texto principal / secundário. `cacau` também é o fundo da faixa de conexão. |
| `creme` / `areia` / `branco` | Fundo da página / blocos que se separam (vazio, esqueleto, abas) / cartões e cabeçalho. |
| `amarelo-oferta` | **Não usado no app.** É cor de preço e promoção; "Aguardando aprovação" usa um ocre próprio. |

Arquivos: logos em `public/brand/` (nomes do manual), fontes em `src/app/fonts/`
(`next/font/local`, servidas pelo próprio app; nada vai ao Google Fonts).

## 3. Cores

Papéis (não nomes de cor): `bg`, `surface`, `surface-muted`, `surface-pressed`, `text`,
`text-muted`, `accent*`, `focus`, `border`, `border-control`, `danger*`, `success*`, `inverse*`,
`notice-*`, `status-*`. Use sempre o papel (`bg-surface`, `text-text-muted`); a paleta padrão do
Tailwind foi removida de propósito.

- **Superfícies por degrau de tom**, nunca por linha grossa: página `bg` → cartão `surface` →
  bloco que se separa `surface-muted` → hover/pressionado `surface-pressed`. Divisória (quando
  inevitável) é `border`, 1px.
- **Contorno de controle** (campo, caixa do checklist, botão secundário) é `border-control`,
  sempre >= 3:1 com o fundo.
- **Texto laranja pequeno** (link, número em destaque) é `accent-text`: a brasa um pouco mais
  escura (`#A83C07`), que passa AA também sobre areia (a brasa pura dá 4,07:1 ali).
- **Foco:** anel de 3px em `focus`, afastado 2px, em todo elemento focável (`:focus-visible`).
- **Tema escuro** (opcional, `next-themes`, classe `.dark`): superfícies derivadas do cacau,
  texto creme, botão primário `laranja-ede` com texto `cacau` (5,02:1). Os dois temas passam AA
  em todos os pares da tabela gerada.
- Prefira tokens a `dark:`. As classes `.light` e `.dark` valem em qualquer elemento (o catálogo
  mostra os dois temas lado a lado).

## 4. Status da tarefa

| Status | Ícone | Forma | Quando |
| --- | --- | --- | --- |
| Pendente | círculo vazio | contorno contínuo, fundo quase igual ao da página | gerada, ainda não iniciada |
| Em andamento | círculo meio cheio | tinta azul clara | tentativa aberta |
| Aguardando aprovação | ampulheta | tinta ocre clara | enviada; **não** é concluída |
| Aprovada | círculo com check | tinta verde clara | a única que conta como concluída |
| Correção solicitada | seta de retorno | fundo de clareza média (ameixa) | reprovada; pede ação de quem executa |
| Atrasada | despertador | **cheia**: escura no claro, clara no escuro | venceu sem envio; o que mais pede ação |
| Cancelada | círculo cortado | contorno **tracejado**, texto apagado | fora do fluxo |

Em escala de cinza ou para daltonismo, os grupos continuam separados pela forma e pela clareza
(o teste confere ΔL\* >= 30 para "Atrasada" e >= 7 para "Correção solicitada"); dentro do grupo de
tintas claras, o ícone e o texto decidem. Componente: `StatusBadge`; mapeamento banco ↔ interface
em `src/lib/design/status.ts`.

## 5. Tipografia

- **Bitter** (800/900) só em: título da página (`type-title-1`), nome de seção (`type-title-2`),
  números grandes (`type-kpi`, `type-counter`) e preço. Nunca em parágrafo, nunca em itálico.
- **Figtree** (400–800) em tudo que se lê: corpo (`type-body`, 16px), rótulo e botão
  (`type-body-strong`), título de tarefa e item (`type-lead`, 18px), metadado (`type-meta`, 14px).
- **Texto corrido >= 16px.** `type-meta` (14px) só para horário, setor, selo; nunca parágrafo.
  O utilitário `text-xs` (12px) foi removido.
- **Números tabulares** (`tabular-nums`) em todo contador, horário, prazo, porcentagem e KPI.
- Caixa alta só em sigla. Sem `uppercase` + `tracking` em rótulo.
- Fallbacks do manual: Rockwell/Georgia (Bitter) e Arial (Figtree), com métrica ajustada pelo
  `next/font` para não pular o layout.

## 6. Espaço, raios, elevação, alvos

- **Espaço:** múltiplos de 8 (manual), mais 4 e 12 quando a interface precisa. No Tailwind
  (`1` = 4px): `1, 2, 3, 4, 6, 8, 10, 12, 16`. Margem lateral da página: 16px no celular.
- **Raios:** `rounded-s` 6px (selo pequeno, miniatura), `rounded-m` 12px (botão, campo, cartão,
  aviso), `rounded-l` 26px (dialog e gaveta), `rounded-full` (selo de status). Outros raios foram
  removidos do Tailwind.
- **Elevação:** só o que flutua tem sombra (`shadow-float` em menu/popover, `shadow-dialog` em
  dialog/gaveta, sombra própria do toast). Cartão, cabeçalho e barra inferior não têm sombra.
- **Alvo de toque >= 44px** (botão `sm` 44, `md` 48, `lg` 56, ícone 44×44; linha do checklist
  >= 56; link de texto com `min-height` 44). Medido no E2E em 390px (`e2e/design.spec.ts`).
- **Polegar:** a ação principal da execução fica na `BottomActionBar` (fixa, com
  `env(safe-area-inset-bottom)`); a página reserva a altura dela.

## 7. Movimento

Tokens exatos (`--ease-out`, `--ease-in-out`, `--ease-drawer`) e durações dentro das faixas do
prompt estão na tabela gerada. Regras:

- Antes de animar: com que frequência isso é visto? Qual o propósito? Ações de 100+/dia e atalhos
  de teclado **não animam**.
- Só `transform` e `opacity`. Nunca `transition: all`, nunca `scale(0)` (comece em 0.95–0.96 +
  opacidade), nunca `ease-in`. Cor de hover troca sem transição.
  Exceções pedidas pelo prompt: o traço do check (`stroke-dashoffset`) e o blur de 2px do envio.
- Pressionar: `scale(0.97)`, 160ms `--ease-out` (`.pressable`); cartão inteiro `scale(0.98)`
  (`.pressable-soft`).
- Hover só em `@media (hover: hover) and (pointer: fine)` (a variante `hover:` do Tailwind foi
  redefinida assim).
- Popover/menu: `transform-origin: var(--transform-origin)` do base-ui. Modal: centralizado,
  opacidade + escala 0.96 → 1, saída mais rápida que a entrada.
- Transições CSS (interrompíveis) em vez de keyframes para toques rápidos. Keyframes só em
  movimento contínuo (indicador e esqueleto).
- `prefers-reduced-motion`: mantém opacidade e cor, tira escala, rotação e deslocamento (o check
  aparece por opacidade; o indicador pulsa em vez de girar; o esqueleto para).

Motion com propósito previsto (o resto não anima):

| Momento | Como | Onde | Fase |
| --- | --- | --- | --- |
| Marcar item do checklist | caixa encolhe ao pressionar + check desenhado (180ms) | `ChecklistItem` | pronto |
| Enviar tarefa | rótulo troca no lugar (Enviar → Enviando… → Enviada) com blur 2px | `SubmitButton` | pronto |
| Reprovar com motivo | dialog com campo obrigatório, sem "segurar para confirmar" | `ReasonDialog` | pronto |
| Tarefa sai de Pendentes e entra em Aguardando | layout animation curta (`--duration-layout`) | lista do Hoje | Fase 3 |
| Foto em tela cheia | gaveta com swipe to dismiss (velocidade > 0,11) e rubber-banding | aprovação | Fase 4 |
| Aprovar todas as pendências do dia | única celebração, discreta | fila do gerente | Fase 4 |
| KPIs | NumberFlow ao mudar o filtro; gráficos sem animação de entrada | painel | Fase 5 |

## 8. Iconografia

Ícones de linha com traço de 2px arredondado numa grade de 24 (o mesmo peso relativo do traço da
casa do logo), em `currentColor`: `text` (cacau), `accent-text` (laranja-brasa) ou a cor do status.
Ficam em `src/components/icons` (SVG inline, sem biblioteca: só o que a interface usa).
Sem `title`, o ícone é decorativo (`aria-hidden`) e o texto ao lado diz o que é; ícone sozinho
(botão de ícone) leva `aria-label` no botão. Emoji nunca.

## 9. Componentes

Todos em `src/components/ui/`, variantes com `cva`, primitivos acessíveis do `@base-ui/react`.

| Componente | Variantes e estados | Notas |
| --- | --- | --- |
| `Button` | `primary`, `secondary`, `ghost`, `danger` (+ `success` só no envio); `sm` 44, `md` 48, `lg` 56, `icon` 44; `loading` (indicador, sem esmaecer), `disabled`, `block` | Link com cara de botão: `buttonVariants()` |
| `SubmitButton` | `idle` → `sending` → `sent` | Largura fixa (rótulos na mesma célula); fim anunciado em `role="status"` |
| `StatusBadge` | 7 status, `sm`/`md` | Cor + ícone + texto, sempre |
| `TaskCard` | status, janela, setor, prioridade (baixa/normal/alta/urgente), tarefa crítica, foto, progresso, responsável, prazo | O título é o link e cobre o cartão; números tabulares |
| `ChecklistItem` | `pending`, `done`, `not_ok` (+ observação obrigatória), crítico, foto obrigatória, só leitura | `role="checkbox"`; linha >= 56px |
| `PhotoCapture` | vazio, prévia, enviando (barra por `scaleX`), erro (com "Tentar de novo"), guardada sem conexão | Casca; câmera real na Fase 3 |
| `EmptyState` | com ou sem ação | Diz o que aconteceu e o que fazer |
| `Skeleton`, `TaskCardSkeleton`, `TaskListSkeleton` | — | Mesma forma do conteúdo; `role="status"` no contêiner |
| `OfflineBanner` | sem conexão (com e sem fila), enviando | "3 envios aguardando conexão" |
| `Notice` | `error`, `success`, `info`, `warning`, ação opcional | Ícone + texto |
| `TextField`, `TextArea` | dica, erro (ícone + texto), desabilitado | `<label>` real, 16px (sem zoom no iOS) |
| `ReasonDialog` | aberto/fechado, erro de campo vazio | `@base-ui/react/dialog`; foco no campo ao abrir |
| `AppShell` / `AppHeader` | com e sem navegação entre áreas | Logo, tema, Sair, quem está logado |
| `BottomActionBar` | fixa (padrão) ou no fluxo | Área segura do aparelho |

## 10. Voz e microcopy

Adaptado do tom de voz da marca para uma ferramenta interna: a melhor colega de loja, que sabe o
que tem de ser feito e fala sem rodeio.

1. **Comece pelo útil.** "Abertura da loja · 07:30–08:15", não "Tarefa de abertura agendada".
2. **Fale com uma pessoa:** "você", frases curtas, verbo no presente.
3. **Erro diz o que aconteceu e o que fazer:** "A foto é obrigatória nesta etapa. Toque em Tirar
   foto." / "Não deu para enviar a foto. Confira a internet e toque em Tentar de novo."
4. **Sem grito:** nada de frase em caixa alta; no máximo uma exclamação por tela (de preferência
   nenhuma). Nada de "imperdível", "atenção!!!", jargão técnico sem explicação.
5. **O sistema registra, não pune:** "Venceu às 08:15", nunca "Você falhou"; o registro não é
   tratado como prova incontestável.
6. **Botão diz a ação:** "Enviar", "Reprovar", "Tentar de novo", "Tirar foto" — não "OK", "Sim".
7. **Vocabulário do produto** (PRODUCT.md §7): Pendente, Em andamento, Aguardando aprovação,
   Aprovada, Correção solicitada, Atrasada, Cancelada; rotina, tentativa, evidência, janela.
8. **Números:** horário "07:30", janela "07:30–08:15" (meia-risca), "3 de 5", plural certo
   ("1 envio", "3 envios").

## 11. Estados de tela (obrigatórios)

| Estado | Como | Componente |
| --- | --- | --- |
| Carregando | esqueleto com a forma do conteúdo; nunca spinner de página inteira | `TaskListSkeleton` |
| Vazio | o que aconteceu + o que vem depois / o que fazer | `EmptyState` |
| Erro | mensagem + ação de recuperar | `Notice tone="error" action=…` |
| Sem conexão | faixa de conexão; a tela continua usável | `OfflineBanner` |

## 12. Acessibilidade (checklist de toda tela)

- Contraste AA nos dois temas (texto 4,5:1; ícone, contorno de controle e foco 3:1): tabela gerada.
- Foco visível em tudo; ordem de foco = ordem visual; "Pular para o conteúdo" nas áreas logadas.
- `alt` em toda imagem (logo: "Éde Utilidades"); ícone decorativo com `aria-hidden`.
- `<label>` real em todo campo; erro ligado por `aria-describedby`.
- Status nunca só por cor; mudança de estado anunciada (`role="status"`/`"alert"`).
- Alvo de toque >= 44px; texto corrido >= 16px.

## 13. Como mudar um token

1. Edite `src/lib/design/tokens.ts` (e, se for um par novo de texto/fundo, inclua em `CONTRAST_PAIRS`).
2. Rode `pnpm tokens` (regrava `src/app/tokens.css` e as tabelas abaixo).
3. Rode `pnpm test` (contraste nos dois temas e sincronia).

## 14. Tabelas geradas

<!-- tokens:inicio (gerado por `pnpm tokens` a partir de src/lib/design/tokens.ts; não edite este bloco) -->

### Cores da interface

Cada papel vira `--<papel>` (CSS) e `bg-<papel>` / `text-<papel>` / `border-<papel>` (Tailwind).

| Papel | Claro | Escuro | Uso |
| --- | --- | --- | --- |
| `bg` | `#FFF4E8` | `#170E09` | Fundo da página (creme da marca no claro; cacau quase preto no escuro). |
| `surface` | `#FFFFFF` | `#221610` | Cartões, cabeçalho, campos, barra de ação: um degrau acima do fundo. |
| `surface-muted` | `#F3E6D6` | `#2E2018` | Blocos que se separam do fundo (areia da marca): estados vazios, esqueleto, faixas. |
| `surface-pressed` | `#EADAC6` | `#3B2A20` | Degrau seguinte: hover (só com mouse) e item pressionado. |
| `text` | `#2A1810` | `#FFF4E8` | Texto principal. |
| `text-muted` | `#6B5A50` | `#CDBBAC` | Texto secundário: horário, setor, legenda, dica de campo. |
| `brand` | `#EE5D06` | `#EE5D06` | Laranja da marca: logo e marcas grandes. Nunca texto pequeno nem fundo de texto pequeno branco. |
| `brand-fg` | `#FFFFFF` | `#FFFFFF` | Logo e título sobre laranja-ede: só texto de 24px+ ou negrito de 19px+ (3,39:1). |
| `brand-pattern` | `#F3711F` | `#F3711F` | Padrão de casas tom sobre tom no painel laranja das páginas públicas. Decorativo, nunca atrás de texto pequeno. |
| `accent` | `#C2470A` | `#EE5D06` | Ação principal (fundo do botão primário), item marcado do checklist, seleção. |
| `accent-hover` | `#A63B07` | `#FF7A2E` | Botão primário com o mouse em cima. |
| `accent-fg` | `#FFFFFF` | `#2A1810` | Texto e ícone sobre `accent` (branco sobre brasa; cacau sobre laranja no escuro). |
| `accent-text` | `#A83C07` | `#FF9A5E` | Laranja de texto pequeno: links e números de destaque. Brasa um pouco mais escura para passar também sobre areia. |
| `focus` | `#C2470A` | `#FF9A5E` | Anel de foco (3px, afastado 2px do elemento). |
| `border` | `#E6D5C0` | `#3B2A20` | Divisória decorativa: degrau de tom, 1px. Nunca linha grossa. |
| `border-control` | `#8C7868` | `#8F7A6B` | Contorno de campo, caixa de seleção e botão secundário (>= 3:1 com o fundo). |
| `danger` | `#B3261E` | `#F2877D` | Fundo do botão de perigo. |
| `danger-hover` | `#951E17` | `#F59D94` | Botão de perigo com o mouse em cima. |
| `danger-fg` | `#FFFFFF` | `#2B0B07` | Texto sobre `danger`. |
| `danger-text` | `#A8241B` | `#FF9C92` | Erro de campo e item não conforme sobre qualquer superfície. |
| `success` | `#1F6E3A` | `#79C58C` | Confirmação forte (botão que virou “Enviada”). |
| `success-fg` | `#FFFFFF` | `#0E2416` | Texto sobre `success`. |
| `inverse` | `#2A1810` | `#F3E6D6` | Faixa invertida (aviso de conexão): o maior contraste possível no sol. |
| `inverse-fg` | `#FFF4E8` | `#2A1810` | Texto sobre `inverse`. |
| `notice-error-bg` | `#FBE4E1` | `#3E1A16` | Aviso de erro (fundo). |
| `notice-error-fg` | `#8E1F17` | `#FFB3AA` | Aviso de erro (texto e ícone). |
| `notice-success-bg` | `#DFEFE1` | `#163421` | Aviso de sucesso (fundo). |
| `notice-success-fg` | `#1B5B2E` | `#ABDDB6` | Aviso de sucesso (texto e ícone). |
| `notice-info-bg` | `#E1EBF5` | `#1B2D42` | Aviso informativo (fundo). |
| `notice-info-fg` | `#1C4A78` | `#BBD6F2` | Aviso informativo (texto e ícone). |
| `notice-warning-bg` | `#FBEDC4` | `#3B2D0C` | Aviso de atenção (fundo). |
| `notice-warning-fg` | `#664500` | `#F4D58E` | Aviso de atenção (texto e ícone). |
| `selection` | `#F9D2B8` | `#5A2E14` | Texto selecionado. |

### Status da tarefa

Sempre cor + ícone + texto. L* = clareza do fundo (0 a 100): atrasada e correção solicitada se
separam das demais pela clareza, não só pelo matiz; pendente e cancelada, pelo contorno.

| Status | Banco | Forma | Claro (fundo · texto · ícone) | Escuro (fundo · texto · ícone) | L* claro / escuro |
| --- | --- | --- | --- | --- | --- |
| Pendente | `pending` | `outline` | `#F7F0E8` · `#4A3A30` · `#6B5A50` | `#2B2019` · `#EDE1D6` · `#C9B7A8` | 95 / 13 |
| Em andamento | `in_progress` | `tint` | `#E1EBF5` · `#1C4A78` · `#2D5F96` | `#1B2D42` · `#BBD6F2` · `#8EB8E6` | 93 / 18 |
| Aguardando aprovação | `submitted` | `tint` | `#FBEDC4` · `#664500` · `#8A5D00` | `#3B2D0C` · `#F4D58E` · `#E3B851` | 94 / 19 |
| Aprovada | `approved` | `tint` | `#DFEFE1` · `#1B5B2E` · `#2A773F` | `#163421` · `#ABDDB6` · `#79C58C` | 93 / 19 |
| Correção solicitada | `rejected` | `strong` | `#E6C3E0` · `#5A1F56` · `#7E3478` | `#5E2D59` · `#FBE3F7` · `#E8A9DF` | 83 / 27 |
| Atrasada | `overdue` | `solid` | `#B3261E` · `#FFFFFF` · `#FFFFFF` | `#F2877D` · `#2B0B07` · `#2B0B07` | 40 / 68 |
| Cancelada | `cancelled` | `dashed` | `#F1ECE7` · `#5C514A` · `#7A6D64` | `#2A221D` · `#BFB2A7` · `#A6988C` | 94 / 14 |

### Contraste conferido (WCAG AA)

Calculado de `tokens.ts` pelo `contrast.test.ts` (4,5:1 texto; 3:1 ícone, contorno de controle, foco e marca).

| Uso | Texto/elemento sobre fundo | Mínimo | Claro | Escuro |
| --- | --- | --- | --- | --- |
| Texto principal | `text` sobre `bg` | 4.5:1 | 15.65:1 | 17.54:1 |
| Texto principal | `text` sobre `surface` | 4.5:1 | 16.98:1 | 16.26:1 |
| Texto principal | `text` sobre `surface-muted` | 4.5:1 | 13.82:1 | 14.48:1 |
| Texto principal | `text` sobre `surface-pressed` | 4.5:1 | 12.40:1 | 12.58:1 |
| Texto secundário | `text-muted` sobre `bg` | 4.5:1 | 6.04:1 | 10.24:1 |
| Texto secundário | `text-muted` sobre `surface` | 4.5:1 | 6.55:1 | 9.49:1 |
| Texto secundário | `text-muted` sobre `surface-muted` | 4.5:1 | 5.33:1 | 8.45:1 |
| Texto secundário | `text-muted` sobre `surface-pressed` | 4.5:1 | 4.78:1 | 7.34:1 |
| Link e número em laranja | `accent-text` sobre `bg` | 4.5:1 | 5.84:1 | 9.09:1 |
| Link e número em laranja | `accent-text` sobre `surface` | 4.5:1 | 6.33:1 | 8.43:1 |
| Link e número em laranja | `accent-text` sobre `surface-muted` | 4.5:1 | 5.15:1 | 7.51:1 |
| Link e número em laranja | `accent-text` sobre `surface-pressed` | 4.5:1 | 4.62:1 | 6.52:1 |
| Erro de campo, item não conforme | `danger-text` sobre `bg` | 4.5:1 | 6.59:1 | 9.44:1 |
| Erro de campo, item não conforme | `danger-text` sobre `surface` | 4.5:1 | 7.15:1 | 8.75:1 |
| Erro de campo, item não conforme | `danger-text` sobre `surface-muted` | 4.5:1 | 5.83:1 | 7.80:1 |
| Erro de campo, item não conforme | `danger-text` sobre `surface-pressed` | 4.5:1 | 5.23:1 | 6.77:1 |
| Botão primário | `accent-fg` sobre `accent` | 4.5:1 | 5.00:1 | 5.01:1 |
| Botão primário (hover) | `accent-fg` sobre `accent-hover` | 4.5:1 | 6.46:1 | 6.53:1 |
| Botão de perigo | `danger-fg` sobre `danger` | 4.5:1 | 6.53:1 | 7.40:1 |
| Botão de perigo (hover) | `danger-fg` sobre `danger-hover` | 4.5:1 | 8.48:1 | 8.78:1 |
| Botão “Enviada” | `success-fg` sobre `success` | 4.5:1 | 6.26:1 | 7.93:1 |
| Faixa de conexão | `inverse-fg` sobre `inverse` | 4.5:1 | 15.65:1 | 13.82:1 |
| Texto selecionado | `text` sobre `selection` | 4.5:1 | 12.08:1 | 10.54:1 |
| Aviso de erro | `notice-error-fg` sobre `notice-error-bg` | 4.5:1 | 7.32:1 | 9.00:1 |
| Aviso de sucesso | `notice-success-fg` sobre `notice-success-bg` | 4.5:1 | 6.80:1 | 8.88:1 |
| Aviso informativo | `notice-info-fg` sobre `notice-info-bg` | 4.5:1 | 7.56:1 | 9.33:1 |
| Aviso de atenção | `notice-warning-fg` sobre `notice-warning-bg` | 4.5:1 | 7.45:1 | 9.41:1 |
| Status “Pendente” (texto) | `status.pendente.fg` sobre `status.pendente.bg` | 4.5:1 | 9.58:1 | 12.34:1 |
| Status “Em andamento” (texto) | `status.em-andamento.fg` sobre `status.em-andamento.bg` | 4.5:1 | 7.56:1 | 9.33:1 |
| Status “Aguardando aprovação” (texto) | `status.aguardando-aprovacao.fg` sobre `status.aguardando-aprovacao.bg` | 4.5:1 | 7.45:1 | 9.41:1 |
| Status “Aprovada” (texto) | `status.aprovada.fg` sobre `status.aprovada.bg` | 4.5:1 | 6.80:1 | 8.88:1 |
| Status “Correção solicitada” (texto) | `status.correcao-solicitada.fg` sobre `status.correcao-solicitada.bg` | 4.5:1 | 7.50:1 | 8.73:1 |
| Status “Atrasada” (texto) | `status.atrasada.fg` sobre `status.atrasada.bg` | 4.5:1 | 6.53:1 | 7.40:1 |
| Status “Cancelada” (texto) | `status.cancelada.fg` sobre `status.cancelada.bg` | 4.5:1 | 6.55:1 | 7.54:1 |
| Status “Pendente” (ícone) | `status.pendente.icon` sobre `status.pendente.bg` | 3:1 | 5.80:1 | 8.17:1 |
| Status “Em andamento” (ícone) | `status.em-andamento.icon` sobre `status.em-andamento.bg` | 3:1 | 5.45:1 | 6.76:1 |
| Status “Aguardando aprovação” (ícone) | `status.aguardando-aprovacao.icon` sobre `status.aguardando-aprovacao.bg` | 3:1 | 4.93:1 | 7.17:1 |
| Status “Aprovada” (ícone) | `status.aprovada.icon` sobre `status.aprovada.bg` | 3:1 | 4.61:1 | 6.57:1 |
| Status “Correção solicitada” (ícone) | `status.correcao-solicitada.icon` sobre `status.correcao-solicitada.bg` | 3:1 | 4.99:1 | 5.59:1 |
| Status “Atrasada” (ícone) | `status.atrasada.icon` sobre `status.atrasada.bg` | 3:1 | 6.53:1 | 7.40:1 |
| Status “Cancelada” (ícone) | `status.cancelada.icon` sobre `status.cancelada.bg` | 3:1 | 4.26:1 | 5.56:1 |
| Anel de foco | `focus` sobre `bg` | 3:1 | 4.60:1 | 9.09:1 |
| Anel de foco | `focus` sobre `surface` | 3:1 | 5.00:1 | 8.43:1 |
| Anel de foco | `focus` sobre `surface-muted` | 3:1 | 4.07:1 | 7.51:1 |
| Anel de foco | `focus` sobre `surface-pressed` | 3:1 | 3.65:1 | 6.52:1 |
| Contorno de campo e caixa de seleção | `border-control` sobre `bg` | 3:1 | 3.87:1 | 4.68:1 |
| Contorno de campo e caixa de seleção | `border-control` sobre `surface` | 3:1 | 4.19:1 | 4.33:1 |
| Contorno de campo e caixa de seleção | `border-control` sobre `surface-muted` | 3:1 | 3.41:1 | 3.86:1 |
| Caixa marcada, controle ativo | `accent` sobre `bg` | 3:1 | 4.60:1 | 5.62:1 |
| Caixa marcada, controle ativo | `accent` sobre `surface` | 3:1 | 5.00:1 | 5.21:1 |
| Caixa marcada, controle ativo | `accent` sobre `surface-muted` | 3:1 | 4.07:1 | 4.64:1 |
| Caixa “não conforme” | `danger-text` sobre `surface` | 3:1 | 7.15:1 | 8.75:1 |
| Logo e marca grande | `brand` sobre `bg` | 3:1 | 3.12:1 | 5.62:1 |
| Logo e marca grande | `brand` sobre `surface` | 3:1 | 3.38:1 | 5.21:1 |
| Título grande (24px+) sobre laranja | `brand-fg` sobre `brand` | 3:1 | 3.38:1 | 3.38:1 |

### Tipografia

| Utilitário | Fonte | Tamanho / linha | Peso | Números | Estilo da marca | Uso |
| --- | --- | --- | --- | --- | --- | --- |
| `type-display` | Bitter | 44 / 48px | 800 | — | display (44px) | Frase do painel das páginas públicas. Nunca no app |
| `type-kpi` | Bitter | 40 / 44px | 900 | tabulares | preco (adaptado) | Número grande de indicador |
| `type-counter` | Bitter | 28 / 32px | 800 | tabulares | titulo-2 | Contadores do Hoje (Pendentes, Atrasadas) |
| `type-title-1` | Bitter | 28 / 34px | 800 | — | titulo-2 | Título da página (até ~6 palavras) |
| `type-title-2` | Bitter | 20 / 26px | 800 | — | titulo-3 | Nome de seção |
| `type-lead` | Figtree | 18 / 26px | 600 | — | destaque (18px) | Título de tarefa, texto do item do checklist |
| `type-body` | Figtree | 16 / 24px | 400 | — | corpo | Texto corrido (mínimo 16px) |
| `type-body-strong` | Figtree | 16 / 24px | 600 | — | destaque | Rótulo de campo, botão, ênfase |
| `type-meta` | Figtree | 14 / 20px | 500 | — | legenda (14px) | Horário, setor, selo de status. Nunca parágrafo |

### Movimento

| Token | Valor | Faixa do prompt | Uso |
| --- | --- | --- | --- |
| `--ease-out` | `cubic-bezier(0.23, 1, 0.32, 1)` | exata | Curva |
| `--ease-in-out` | `cubic-bezier(0.77, 0, 0.175, 1)` | exata | Curva |
| `--ease-drawer` | `cubic-bezier(0.32, 0.72, 0, 1)` | exata | Curva |
| `--duration-press` | 160ms | 100–160ms | Botão e item pressionado (scale 0.97) |
| `--duration-popover` | 180ms | 125–200ms | Tooltip e popover |
| `--duration-dropdown` | 200ms | 150–250ms | Menu e select |
| `--duration-modal` | 240ms | 200–300ms | Dialog (centralizado) |
| `--duration-drawer` | 280ms | 200–300ms | Gaveta de foto (a velocidade do gesto manda) |
| `--duration-check` | 180ms | 100–200ms | Check desenhado do checklist |
| `--duration-morph` | 200ms | 150–250ms | Botão Enviar → Enviada (blur ≤ 2px) |
| `--duration-layout` | 220ms | 150–300ms | Tarefa sai de Pendentes e entra em Aguardando |

### Raios, espaços, sombras e alvos

| Token | Valor | Uso |
| --- | --- | --- |
| `rounded-s` | 6px (raio-s) | Selos pequenos, miniatura de foto, marcador de crítico |
| `rounded-m` | 12px (raio-m) | Botões, campos, cartões, avisos |
| `rounded-l` | 26px (raio-l) | Dialog e gaveta (superfícies que flutuam), ícone do app |
| `rounded-full` | 999px (raio-pilula) | Selo de status, contador |
| `espaços` | 4 · 8 · 12 · 16 · 24 · 32 · 40 · 48 · 64 px | Tailwind `1`=4px: use 1, 2, 3, 4, 6, 8, 10, 12, 16 |
| `shadow-float` | — | Menu, popover |
| `shadow-dialog` | — | Dialog e gaveta |
| `--touch-min` | 44px | Alvo de toque mínimo |
| `--control-height` | 48px | Altura de botão e campo |
| `--bar-height` | 56px | Botão da barra inferior de ação |

<!-- tokens:fim -->
