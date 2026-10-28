import 'package:supabase_flutter/supabase_flutter.dart';

const singleFamilyMembershipMessage =
    'You already belong to a family. Joining another family is not available yet.';

bool isSingleFamilyMembershipError(Object error) =>
    error is PostgrestException && error.message == 'FAMILY_MEMBERSHIP_LIMIT';
