import { describe, expect, it, vi } from "vitest";

import { MAX_SIGNED_URL_SECONDS, createSignedReadUrl, signedUrlTtl } from "./signed-url";

describe("signedUrlTtl", () => {
  it("padrão de 5 min", () => {
    expect(signedUrlTtl()).toBe(300);
    expect(MAX_SIGNED_URL_SECONDS).toBe(300);
  });

  // R3-ISOLAMENTO-01: o link não pode durar mais que 5 min (PDF: signed URL ≤ 5 min no servidor).
  it.each([301, 3600, 315_360_000, 0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])(
    "recusa prazo %s",
    (seconds) => {
      expect(() => signedUrlTtl(seconds)).toThrow(RangeError);
    },
  );

  it("aceita de 1 a 300 segundos", () => {
    expect(signedUrlTtl(1)).toBe(1);
    expect(signedUrlTtl(60)).toBe(60);
    expect(signedUrlTtl(300)).toBe(300);
  });
});

describe("createSignedReadUrl", () => {
  const path = "org/loja/tarefa/tentativa/foto.jpg";

  it("só assina depois da conferência como o usuário, com no máximo 5 min", async () => {
    const canRead = vi.fn().mockResolvedValue(true);
    const sign = vi.fn().mockResolvedValue("https://exemplo.local/assinada");
    await expect(createSignedReadUrl({ canRead, sign }, "evidences", path)).resolves.toBe(
      "https://exemplo.local/assinada",
    );
    expect(canRead).toHaveBeenCalledWith("evidences", path);
    expect(sign).toHaveBeenCalledWith("evidences", path, 300);
  });

  it("sem permissão, não assina nada", async () => {
    const canRead = vi.fn().mockResolvedValue(false);
    const sign = vi.fn();
    await expect(createSignedReadUrl({ canRead, sign }, "references", path)).resolves.toBeNull();
    expect(sign).not.toHaveBeenCalled();
  });

  it("prazo acima de 5 min falha antes de conferir ou assinar", async () => {
    const canRead = vi.fn();
    const sign = vi.fn();
    await expect(createSignedReadUrl({ canRead, sign }, "evidences", path, 3600)).rejects.toThrow(
      RangeError,
    );
    expect(canRead).not.toHaveBeenCalled();
    expect(sign).not.toHaveBeenCalled();
  });
});
