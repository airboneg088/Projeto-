import { describe, expect, it } from "vitest";

import { STATUS_ICON, isDone, statusFromDb, statusLabel } from "./status";
import { STATUS_KEYS } from "./tokens";

describe("status da tarefa na interface", () => {
  it("cada status tem um ícone diferente (silhueta, não só cor)", () => {
    const icons = STATUS_KEYS.map((key) => STATUS_ICON[key]);
    expect(new Set(icons).size).toBe(STATUS_KEYS.length);
  });

  it("traduz o status do banco", () => {
    expect(statusFromDb("submitted")).toBe("aguardando-aprovacao");
    expect(statusFromDb("rejected")).toBe("correcao-solicitada");
    expect(statusFromDb("overdue")).toBe("atrasada");
    expect(statusFromDb("qualquer")).toBeNull();
    expect(statusFromDb("__proto__")).toBeNull();
  });

  it("rótulos do vocabulário do produto", () => {
    expect(STATUS_KEYS.map(statusLabel)).toEqual([
      "Pendente",
      "Em andamento",
      "Aguardando aprovação",
      "Aprovada",
      "Correção solicitada",
      "Atrasada",
      "Cancelada",
    ]);
  });

  it("só aprovada conta como concluída; aguardando aprovação não", () => {
    expect(STATUS_KEYS.filter(isDone)).toEqual(["aprovada"]);
    expect(isDone("aguardando-aprovacao")).toBe(false);
  });
});
