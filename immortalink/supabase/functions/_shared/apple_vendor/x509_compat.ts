import { Buffer } from "node:buffer";
import { KeyObject, X509Certificate as NativeCertificate } from "node:crypto";
import { X509 } from "npm:jsrsasign@11.1.5";

// Deno 2.1 lacks these four Node methods. Keep Apple's verifier unchanged;
// supply them through the same certificate library its OCSP verifier uses.
export class X509Certificate {
  private readonly native: NativeCertificate;
  private readonly der: Buffer;
  private readonly parsed: X509;

  constructor(input: Buffer) {
    this.native = new NativeCertificate(input);
    const text = input.toString("utf8");
    this.der = text.startsWith("-----BEGIN CERTIFICATE-----")
      ? Buffer.from(text.replace(/-----BEGIN CERTIFICATE-----|-----END CERTIFICATE-----|\s/g, ""), "base64")
      : Buffer.from(input);
    this.parsed = new X509();
    this.parsed.readCertHex(this.der.toString("hex"));
  }

  get raw(): Buffer { return Buffer.from(this.der); }
  get publicKey(): KeyObject { return this.native.publicKey; }
  get subject(): string { return this.native.subject; }
  get issuer(): string { return this.native.issuer; }
  get ca(): boolean { return this.native.ca; }
  get validFrom(): string { return this.native.validFrom; }
  get validTo(): string { return this.native.validTo; }

  toString(): string {
    return `-----BEGIN CERTIFICATE-----\n${this.der.toString("base64").match(/.{1,64}/g)!.join("\n")}\n-----END CERTIFICATE-----\n`;
  }

  get infoAccess(): string | undefined {
    const urls = this.parsed.getExtAIAInfo()?.ocsp;
    return urls?.map((url: string) => `OCSP - URI:${url}`).join("\n");
  }

  verify(publicKey: KeyObject): boolean {
    return this.parsed.verifySignature(publicKey.export({ type: "spki", format: "pem" }));
  }
}
