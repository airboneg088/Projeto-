# Éde Gestão — site

Versão em site (link do claude.ai) do Éde Gestão. Cada loja (Primavera, Castro Alves, Parque América) tem o seu portal: a equipe da loja, o quadro de tarefas e as aprovações. Os dados ficam no banco do próprio artifact e são compartilhados por todos que abrem o link (pessoas da organização no claude.ai com acesso de Contribuidor ou mais).

- Publicado em: https://claude.ai/artifact/CmvnWFnFwwWfmN36J6iSeL
- `index.html`: o site inteiro (HTML, CSS e JavaScript, sem build).
- `img/`: logo da Éde (brand book).
- `seed/`: configuração inicial gravada no banco — `org.json` (`config/org`), `rotinas.json` (`config/rotinas`: 8 diárias, 4 do mês e 2 “a cada 7 dias”) e `portais.json` (`portais/<loja>`: funcionários de exemplo e quem faz cada rotina por padrão). Nomes com “(exemplo)” são fictícios.
- `local/ede-gestao.html`: o mesmo site em um arquivo só, para abrir direto no computador ou no celular, sem o claude.ai. Gerado por `node site/local/montar.mjs` a partir do `index.html` e do `seed/`.
- `teste/run.mjs`: teste ponta a ponta com uma simulação local da plataforma, incluindo o arquivo local (`node site/teste/run.mjs`; precisa do ffmpeg; `CHROME_PATH` se o Playwright não achar o navegador).

## Como funciona

1. Escolhe o portal da loja e depois “Quem está usando?” (o nome do funcionário ou Gerência).
2. Gerência:
   - **Início**: o que precisa de atenção (ex.: “Faz 12 dias que não fazem ‘Limpeza das mercadorias de cima’”, rotina que ficou dias sem fazer, dia da semana em que ela falha, envio que costuma atrasar, item com problema repetido) e o desempenho de cada pessoa (tarefas abertas agora, aprovadas e pontos, tempo para terminar, ritmo comparado com a média da loja, no prazo e correções).
   - **Quadro**: cada coluna é uma pessoa; arrasta o cartão para quem vai fazer (no celular, segura o cartão um instante e arrasta) ou toca no cartão e marca uma ou mais pessoas. Tarefa em equipe aparece na coluna de cada uma; arrastar para outra pessoa pergunta se fazem juntos ou se troca. Alterna entre **Diárias de hoje** e **Do mês**. **Nova tarefa** cria uma avulsa, já com uma ou mais pessoas.
   - **Aprovar** mostra fotos e vídeos enviados; aprova ou pede correção com motivo. **Equipe** cadastra funcionários e o PIN da gerência. **Mais › Rotinas** mostra a última vez de cada rotina e define quem faz por padrão (uma ou mais pessoas).
3. Funcionário: vê as tarefas dele (hoje e do mês), começa, marca os itens, tira foto ou grava vídeo e envia para aprovação. Em tarefa de equipe, quem chega depois toca em **Ajudar nesta tarefa**: o envio é um só e o que cada um marca aparece para todos.

## Como a análise entende a rotina

- Diária: olha os últimos 14 dias (e 60 para o padrão por dia da semana). Avisa quando ficou 2 ou mais dias seguidos sem fazer, quando foi feita em menos de 70% dos dias, quando um dia da semana quase nunca é feito e quando costuma ser enviada depois do horário.
- A cada N dias (`tipo: "periodica"`, `cadaDias`): entra sozinha no quadro do dia quando passou N dias desde a última vez e volta todo dia até ser feita; o Início avisa quantos dias faz.
- Do mês: avisa quando a do mês atrasou e quando a do mês passado ficou sem fazer.
- Item marcado “Com problema” 2 ou mais vezes em 14 dias vira aviso, com o último relato.
- Uma tarefa avulsa conta como a rotina quando o texto bate com as `palavras` da rotina (ex.: “limpar as prateleiras do alto” conta como “Limpeza das mercadorias de cima”).

## Arquivo local

`local/ede-gestao.html` abre direto no navegador (dois cliques no computador; no celular, abrir pelo app de arquivos ou pelo navegador). Os dados ficam só naquele aparelho e naquele navegador; a cópia dos dados (um arquivo `.txt`, uma linha por registro) é salva pela tela de portais ou em **Gerência › Mais**, e restaurada em **Gerência › Mais** (inclusive em outro aparelho). Sem o claude.ai, cada aparelho tem os seus próprios dados: para a equipe toda usar junto, use o link publicado.

- Use uma aba só: se o arquivo for aberto de novo, a aba antiga para de gravar e avisa.
- O PIN da gerência vale para todos no arquivo local. **Esqueci o PIN** (na tela do PIN) salva uma cópia, apaga o PIN e deixa um aviso no Início e em Equipe.
- Fotos e vídeos ficam no aparelho e não são apagados sozinhos; com o tempo, salve a cópia e libere espaço.

## Dados no banco

| Caminho | O que guarda |
|---|---|
| `config/org`, `config/rotinas` | lojas, setores e rotinas (só a proprietária altera) |
| `portais/<loja>` | funcionários, responsável padrão por rotina e o hash do PIN |
| `diarias/<loja>_<AAAA-MM-DD>` | tarefas do dia (criadas sozinhas a partir das rotinas); `responsaveis` lista quem faz (tarefas antigas têm só `responsavel`) |
| `mensais/<loja>_<AAAA-MM>` | tarefas do mês |
| `midias/<id>` (+ `partes/<n>`) | foto ou vídeo de cada envio; o arquivo vai para o armazenamento do site quando a conta pode enviar, senão fica no banco (vídeo reduzido e em partes) |

Limites conhecidos: o PIN evita engano no aparelho da loja, mas não é senha forte (quem tem acesso ao link consegue ler o banco). O banco aceita até 25 mil documentos; com o uso diário, as mídias antigas vão precisar de limpeza periódica.

O sistema completo (Next.js + Supabase, com RLS e testes) continua neste repositório para quando a operação precisar de produção própria.
