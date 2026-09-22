import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Never include server messages, request URLs, IDs or exception text in UI.
bool isConnectionFailure(Object error) =>
    error is http.ClientException || error is TimeoutException;

String publicErrorMessage(Object error) {
  if (isConnectionFailure(error)) {
    return 'We could not connect. Check your internet connection and try again.';
  }
  if (error is AuthException) {
    return 'We could not verify your session. Reconnect and sign in again.';
  }
  if (error is PostgrestException && error.code == '42501') {
    return 'You do not have permission to complete this action.';
  }
  return 'Something went wrong. Please try again.';
}
