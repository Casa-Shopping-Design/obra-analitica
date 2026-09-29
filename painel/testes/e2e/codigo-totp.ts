import { createHmac } from "node:crypto";

const alfabetoBase32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const passoSegundos = 30;

function decodificarBase32(segredo: string): Buffer {
  const limpo = segredo.replace(/[\s=]/g, "").toUpperCase();
  const bytes: number[] = [];
  let acumulado = 0;
  let bits = 0;
  for (const letra of limpo) {
    const valor = alfabetoBase32.indexOf(letra);
    if (valor < 0) throw new Error("chave do autenticador fora do alfabeto base32");
    acumulado = (acumulado << 5) | valor;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.push((acumulado >> bits) & 0xff);
    }
  }
  return Buffer.from(bytes);
}

function janelaTotp(instante: number): number {
  return Math.floor(instante / 1000 / passoSegundos);
}

// RFC 6238 com SHA-1, seis dígitos e passo de 30 s: o que o Supabase Auth e os aplicativos autenticadores usam.
export function gerarCodigoTotp(segredo: string, instante: number = Date.now()): string {
  const contador = Buffer.alloc(8);
  contador.writeBigUInt64BE(BigInt(janelaTotp(instante)));
  const resumo = createHmac("sha1", decodificarBase32(segredo)).update(contador).digest();
  const inicio = resumo[resumo.length - 1] & 0x0f;
  const numero = resumo.readUInt32BE(inicio) & 0x7fffffff;
  return String(numero % 1_000_000).padStart(6, "0");
}
