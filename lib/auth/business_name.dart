import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';

/// The shop's name for an id in the token, best-effort.
///
/// A failed lookup falls back to the id: not being able to read a name must
/// not lock someone out of scanning, and the id is still enough to tell two
/// shops apart.
final businessNameProvider = FutureProvider.autoDispose.family<String, String>((
  ref,
  businessId,
) async {
  try {
    return await ref.read(apiClientProvider).fetchBusinessName(businessId);
  } catch (_) {
    return businessId;
  }
});
