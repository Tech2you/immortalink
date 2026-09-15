import { Buffer } from "node:buffer";
import {
  Environment,
  SignedDataVerifier,
  VerificationException,
  VerificationStatus,
} from "npm:@apple/app-store-server-library@3.1.0";

// Apple Root CA G3, from https://www.apple.com/certificateauthority/AppleRootCA-G3.cer.
// Pin the trust anchor locally; never trust a root supplied in a notification.
const appleRootG3 = `-----BEGIN CERTIFICATE-----
MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwS
QXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9u
IEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcN
MTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBS
b290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9y
aXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49
AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtf
TjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517
IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySr
MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gA
MGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4
at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM
6BgD56KyKA==
-----END CERTIFICATE-----`;

export function createNotificationVerifier(
  environment: string,
  bundleId: string,
  appAppleId?: string,
) {
  if (environment !== "sandbox" && environment !== "production") {
    throw new Error("Invalid APPLE_IAP_ENVIRONMENT");
  }
  const id = appAppleId ? Number(appAppleId) : undefined;
  if (
    environment === "production" &&
    (!id || !Number.isSafeInteger(id) || id <= 0)
  ) {
    throw new Error("Production notifications require APPLE_APP_ID");
  }
  return new SignedDataVerifier(
    [Buffer.from(appleRootG3)],
    true,
    environment === "production" ? Environment.PRODUCTION : Environment.SANDBOX,
    bundleId,
    id,
  );
}

export async function verifyNotification(
  signedPayload: unknown,
  verifier: Pick<
    SignedDataVerifier,
    "verifyAndDecodeNotification" | "verifyAndDecodeTransaction"
  >,
) {
  if (
    typeof signedPayload !== "string" || !signedPayload ||
    signedPayload.length > 128_000
  ) {
    throw new VerificationException(VerificationStatus.FAILURE);
  }
  const notification = await verifier.verifyAndDecodeNotification(
    signedPayload,
  );
  const signedTransaction = notification.data?.signedTransactionInfo;
  const transaction = signedTransaction
    ? await verifier.verifyAndDecodeTransaction(signedTransaction)
    : null;
  return { notification, transaction };
}

export function notificationErrorStatus(error: unknown): number {
  if (error instanceof VerificationException) {
    return error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
      ? 503
      : 400;
  }
  // Configuration, Apple API and database failures must remain retryable.
  return 503;
}
