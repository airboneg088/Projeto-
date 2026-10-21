import { describe, expect, it, vi } from "vitest";

import {
  MAX_SIGNED_URL_SECONDS,
  createSignedReadUrl,
  isCanonicalStoragePath,
  signedUrlTtl,
} from "./signed-url";

const ORG_A = "0a000000-0000-4000-8000-00000000000a";
const LOJA_P = "0b000000-0000-4000-8000-00000000000b";
const TAREFA_P = "0c000000-0000-4000-8000-00000000000c";
const TENTATIVA_P = "0d000000-0000-4000-8000-00000000000d";
const FOTO_P = "0e000000-0000-4000-8000-00000000000e";
const ORG_B = "1a000000-0000-4000-8000-00000000001a";
const LOJA_B = "1b000000-0000-4000-8000-00000000001b";
const TAREFA_B = "1c000000-0000-4000-8000-00000000001c";
const TENTATIVA_B = "1d000000-0000-4000-8000-00000000001d";
const FOTO_B = "1e000000-0000-4000-8000-00000000001e";

const FOTO_DA_TENTATIVA = `${ORG_A}/${LOJA_P}/${TAREFA_P}/${TENTATIVA_P}/${FOTO_P}.jpg`;
const FOTO_DA_ORG_B = `${ORG_B}/${LOJA_B}/${TAREFA_B}/${TENTATIVA_B}/${FOTO_B}.jpg`;
const PREFIXO_PROPRIO = `${ORG_A}/${LOJA_P}/${TAREFA_P}/${TENTATIVA_P}`;

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

describe("isCanonicalStoragePath", () => {
  it("aceita só o formato exato de cada bucket", () => {
    expect(isCanonicalStoragePath("evidences", FOTO_DA_TENTATIVA)).toBe(true);
    expect(isCanonicalStoragePath("references", `${ORG_A}/rede/${TAREFA_P}/${FOTO_P}.png`)).toBe(
      true,
    );
    expect(
      isCanonicalStoragePath("references", `${ORG_A}/${LOJA_P}/${TAREFA_P}/${FOTO_P}.webp`),
    ).toBe(true);
    // Formato do outro bucket, maiúsculas, extensão errada, sobra no fim
    expect(isCanonicalStoragePath("references", FOTO_DA_TENTATIVA)).toBe(false);
    expect(isCanonicalStoragePath("evidences", FOTO_DA_TENTATIVA.toUpperCase())).toBe(false);
    expect(isCanonicalStoragePath("evidences", FOTO_DA_TENTATIVA.replace(".jpg", ".png"))).toBe(
      false,
    );
    expect(isCanonicalStoragePath("evidences", `${FOTO_DA_TENTATIVA}\n`)).toBe(false);
    expect(isCanonicalStoragePath("evidences", null)).toBe(false);
  });
});

// R4-ISOLAMENTO-01 / R4-INTEGRIDADE-02: o storage-js concatena o caminho na URL e o fetch a
// normaliza ("\\" vira "/", ".." sobe um nível, "%2e" é ponto). Um caminho que o banco
// conferisse como "da própria tentativa" seria assinado como o arquivo de outra organização.
describe("createSignedReadUrl recusa caminho que a URL resolveria para outro objeto", () => {
  const atalhos = [
    `${PREFIXO_PROPRIO}/..\\..\\..\\..\\${FOTO_DA_ORG_B.replaceAll("/", "\\")}`,
    `${PREFIXO_PROPRIO}/../../../../${FOTO_DA_ORG_B}`,
    `${PREFIXO_PROPRIO}/%2e%2e%2f%2e%2e%2f%2e%2e%2f%2e%2e%2f${FOTO_DA_ORG_B}`,
    `${PREFIXO_PROPRIO}/%2E%2E%5C${FOTO_P}.jpg`,
    `${ORG_A}/rede/x/..\\..\\..\\..\\evidences\\${FOTO_DA_ORG_B.replaceAll("/", "\\")}`,
    `${PREFIXO_PROPRIO}/qualquer?coisa#aqui`,
    `/${FOTO_DA_TENTATIVA}`,
    `${PREFIXO_PROPRIO}/./${FOTO_P}.jpg`,
  ];

  it("o atalho resolve mesmo para o arquivo da organização B (por isso é recusado)", () => {
    const base = "http://127.0.0.1:54321/storage/v1/object/sign/evidences/";
    expect(new URL(`${base}${atalhos[0]}`).pathname).toBe(
      `/storage/v1/object/sign/evidences/${FOTO_DA_ORG_B}`,
    );
  });

  it.each(atalhos)("%s: nem confere nem assina", async (path) => {
    const canRead = vi.fn().mockResolvedValue(true);
    const sign = vi.fn().mockResolvedValue("https://exemplo.local/assinada");
    await expect(createSignedReadUrl({ canRead, sign }, "evidences", path)).resolves.toBeNull();
    await expect(createSignedReadUrl({ canRead, sign }, "references", path)).resolves.toBeNull();
    expect(canRead).not.toHaveBeenCalled();
    expect(sign).not.toHaveBeenCalled();
  });
});

describe("createSignedReadUrl", () => {
  const path = FOTO_DA_TENTATIVA;

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
    await expect(createSignedReadUrl({ canRead, sign }, "evidences", path)).resolves.toBeNull();
    expect(canRead).toHaveBeenCalledWith("evidences", path);
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
