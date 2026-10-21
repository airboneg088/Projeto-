/** Formatação de datas e números para a interface (pt-BR, fuso da loja). */

export const STORE_TIME_ZONE = "America/Sao_Paulo";

/** "terça-feira, 21 de outubro" no fuso da loja. */
export function formatLongDate(date: Date, timeZone = STORE_TIME_ZONE): string {
  return new Intl.DateTimeFormat("pt-BR", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone,
  }).format(date);
}

/** "07:30" no fuso da loja. */
export function formatTime(date: Date, timeZone = STORE_TIME_ZONE): string {
  return new Intl.DateTimeFormat("pt-BR", {
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZone,
  }).format(date);
}
