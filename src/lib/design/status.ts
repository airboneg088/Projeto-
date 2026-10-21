import { STATUS, STATUS_KEYS, type StatusKey } from "./tokens";

/**
 * Status da tarefa na interface: rótulo, ícone e valor do banco (PRODUCT.md §7).
 * O nome do ícone é a chave do componente em StatusBadge; cada status tem o seu.
 */
export const STATUS_ICON = {
  pendente: "pending",
  "em-andamento": "in-progress",
  "aguardando-aprovacao": "awaiting",
  aprovada: "approved",
  "correcao-solicitada": "return",
  atrasada: "alarm",
  cancelada: "cancelled",
} as const satisfies Record<StatusKey, string>;

export type StatusIconName = (typeof STATUS_ICON)[StatusKey];

export type DbTaskStatus = (typeof STATUS)[StatusKey]["db"];

const BY_DB = new Map<string, StatusKey>(STATUS_KEYS.map((key) => [STATUS[key].db, key]));

/** Status do banco (`pending`, `submitted`…) → chave da interface. `null` se desconhecido. */
export function statusFromDb(value: string): StatusKey | null {
  return BY_DB.get(value) ?? null;
}

export function statusLabel(key: StatusKey): string {
  return STATUS[key].label;
}

/** Só `approved` conta como concluída (princípio central). */
export function isDone(key: StatusKey): boolean {
  return key === "aprovada";
}
