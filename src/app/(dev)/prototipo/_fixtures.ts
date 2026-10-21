/**
 * Dados de EXEMPLO do catálogo de componentes. Nada aqui é real: pessoas e observações levam
 * "[EXEMPLO]"; lojas, setores e rotinas seguem o vocabulário do supabase/seed.sql (também
 * provisório até a cliente confirmar).
 */
import type { ChecklistValue } from "@/components/ui/checklist-item";
import type { TaskCardProps } from "@/components/ui/task-card";

export const LOJAS = ["Primavera", "Castro Alves", "Parque América"] as const;

export const SETORES = ["Salão de vendas", "Estoque", "Caixa", "Limpeza"] as const;

/** As 8 rotinas-padrão do seed, com setor e janela dos agendamentos. */
export const ROTINAS = [
  {
    title: "Abertura da loja",
    sector: "Salão de vendas",
    start: "07:30",
    end: "08:15",
    priority: "high",
  },
  { title: "Caixa", sector: "Caixa", start: "07:45", end: "08:30", priority: "high" },
  {
    title: "Salão de vendas",
    sector: "Salão de vendas",
    start: "08:15",
    end: "10:00",
    priority: "normal",
  },
  {
    title: "Precificação",
    sector: "Salão de vendas",
    start: "10:00",
    end: "12:00",
    priority: "normal",
  },
  { title: "Reposição", sector: "Estoque", start: "13:00", end: "15:00", priority: "normal" },
  { title: "Estoque", sector: "Estoque", start: "15:00", end: "17:00", priority: "normal" },
  { title: "Limpeza", sector: "Limpeza", start: "17:00", end: "18:30", priority: "normal" },
  { title: "Fechamento da loja", sector: "Caixa", start: "21:30", end: "22:00", priority: "high" },
] as const satisfies ReadonlyArray<{
  title: string;
  sector: (typeof SETORES)[number];
  start: string;
  end: string;
  priority: TaskCardProps["priority"];
}>;

export const PESSOA = "[EXEMPLO] Colaborador 1 Primavera";
export const PESSOA_CURTA = "[EXEMPLO] Colaborador 1";
export const GERENTE = "[EXEMPLO] Gerente Primavera";

type Rotina = (typeof ROTINAS)[number];

function card(
  rotina: Rotina,
  extra: Omit<TaskCardProps, "title" | "windowStart" | "windowEnd" | "sector" | "priority"> &
    Partial<Pick<TaskCardProps, "priority">>,
): TaskCardProps {
  return {
    title: rotina.title,
    windowStart: rotina.start,
    windowEnd: rotina.end,
    sector: rotina.sector,
    priority: rotina.priority,
    ...extra,
  };
}

const [abertura, caixa, salao, precificacao, reposicao, estoque, limpeza, fechamento] = ROTINAS;

/** Um cartão por status, na ordem do dia. */
export const TAREFAS: TaskCardProps[] = [
  card(abertura, {
    status: "atrasada",
    critical: true,
    progress: { done: 2, total: 5 },
    deadlineNote: "Venceu às 08:15",
    requiresPhoto: true,
  }),
  card(caixa, { status: "aprovada", critical: true, progress: { done: 5, total: 5 } }),
  card(salao, {
    status: "em-andamento",
    progress: { done: 3, total: 6 },
    deadlineNote: "Faltam 25 min",
  }),
  card(precificacao, { status: "aguardando-aprovacao", progress: { done: 4, total: 4 } }),
  card(reposicao, {
    status: "correcao-solicitada",
    progress: { done: 3, total: 4 },
    deadlineNote: "Refazer até 15:00",
  }),
  card(estoque, { status: "pendente", progress: { done: 0, total: 5 } }),
  card(limpeza, {
    status: "pendente",
    requiresPhoto: true,
    assignee: PESSOA_CURTA,
    progress: { done: 0, total: 4 },
    priority: "urgent",
  }),
  card(fechamento, { status: "cancelada", priority: "low" }),
];

/** Itens da rotina "Abertura da loja" (seed), com respostas variadas. */
export const CHECKLIST_ABERTURA: Array<{
  text: string;
  critical: boolean;
  requiresPhoto: boolean;
  value: ChecklistValue;
  note?: string;
}> = [
  {
    text: "Desligar o alarme e conferir se não há sinais de arrombamento",
    critical: true,
    requiresPhoto: false,
    value: "done",
  },
  {
    text: "Acender as luzes do salão e ligar computadores, PDV e ar-condicionado",
    critical: false,
    requiresPhoto: false,
    value: "not_ok",
    note: "[EXEMPLO] Ar-condicionado não liga. Técnico chamado.",
  },
  {
    text: "Corredores livres, sem caixas ou mercadorias no caminho",
    critical: true,
    requiresPhoto: true,
    value: "pending",
  },
  {
    text: "Vidros, porcelanas e cerâmicas em altura segura, longe da borda das prateleiras",
    critical: true,
    requiresPhoto: true,
    value: "pending",
  },
  {
    text: "Portas abertas no horário, com fachada e vitrine limpas",
    critical: false,
    requiresPhoto: true,
    value: "pending",
  },
];

/**
 * "Foto" de exemplo: desenho de um corredor com prateleiras (SVG em data:, permitido pela CSP).
 * Não é foto de verdade de nenhuma loja.
 */
const FOTO_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 300">
<rect width="400" height="300" fill="#d8c6b1"/>
<rect y="210" width="400" height="90" fill="#bfa98f"/>
<polygon points="150,210 250,210 330,300 70,300" fill="#cdb79c"/>
<g fill="#8a6f58"><rect x="10" y="40" width="120" height="8"/><rect x="10" y="100" width="120" height="8"/><rect x="10" y="160" width="120" height="8"/><rect x="270" y="40" width="120" height="8"/><rect x="270" y="100" width="120" height="8"/><rect x="270" y="160" width="120" height="8"/></g>
<g fill="#ee5d06"><rect x="20" y="14" width="22" height="26" rx="3"/><rect x="48" y="20" width="30" height="20" rx="3"/><rect x="290" y="74" width="26" height="26" rx="3"/></g>
<g fill="#fff4e8"><rect x="86" y="18" width="34" height="22" rx="3"/><rect x="24" y="74" width="40" height="26" rx="3"/><rect x="322" y="12" width="30" height="28" rx="3"/><rect x="286" y="134" width="44" height="26" rx="3"/></g>
<g fill="#6b5a50"><rect x="72" y="80" width="26" height="20" rx="3"/><rect x="40" y="136" width="30" height="24" rx="3"/><rect x="340" y="80" width="38" height="20" rx="3"/><rect x="340" y="138" width="34" height="22" rx="3"/></g>
</svg>`;

export const FOTO_EXEMPLO = `data:image/svg+xml;charset=utf-8,${encodeURIComponent(FOTO_SVG)}`;
export const FOTO_ALT =
  "[EXEMPLO] Desenho de um corredor livre, com prateleiras arrumadas dos dois lados";
