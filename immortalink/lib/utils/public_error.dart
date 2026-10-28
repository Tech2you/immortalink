import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_membership_limit.dart';

// Never include server messages, request URLs, IDs or exception text in UI.
bool isConnectionFailure(Object error) =>
    error is http.ClientException ||
    error is TimeoutException ||
    error is AuthRetryableFetchException;

String publicErrorMessage(Object error) {
  if (isSingleFamilyMembershipError(error)) {
    return singleFamilyMembershipMessage;
  }
  if (isConnectionFailure(error)) {
    return 'We could not connect. Check your internet connection and try again.';
  }
  if (error is AuthException ||
      (error is PostgrestException && error.code == '401')) {
    return 'We could not verify your session. Reconnect and sign in again.';
  }
  if (error is PostgrestException &&
      (error.code == '42501' || error.code == '403')) {
    return 'You do not have permission to complete this action.';
  }
  return 'Something went wrong. Please try again.';
}
