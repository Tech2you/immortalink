# Apple verifier runtime compatibility

`jws_verification.ts` is Apple's MIT-licensed v3.1.0 source from:
https://github.com/apple/app-store-server-library-node/blob/v3.1.0/jws_verification.ts

Imports are adapted: pinned npm ESM imports, explicit Buffer, external model
imports from the same release, and `X509Certificate` from `x509_compat.ts`.
Header base64url decoding uses Buffer rather than the CommonJS base64url import;
the Error.cause declaration has the TypeScript override modifier.
Certificate-chain rules, Apple purpose extensions, dates, OCSP revocation checks,
bundle/environment checks and validation logic are unchanged. The final JWS
verification uses pinned `jose` WebCrypto with Apple's ES256 algorithm explicitly
required; Deno 2.1's incomplete Node EC curve metadata breaks `jsonwebtoken.verify`.
Do not disable online checks in the live factory to work around runtime failures.

Supabase's deployed Deno 2.1.4 compatibility runtime lacks native certificate
`raw`, `toString`, `infoAccess` and `verify`. The adapter supplies these via the
same pinned jsrsasign dependency already used by Apple's verifier. It does not
patch global crypto or accept roots supplied in incoming messages.

Run verifier tests under both Deno 2.1.4 and the local current runtime. A passing
test on the newer runtime alone missed this production incompatibility.
