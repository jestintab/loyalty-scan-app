import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import 'auth_notifier.dart';

/// Names for the ids in the token, best-effort. A failed lookup falls back to
/// the id: not being able to read a name must not lock someone out of scanning.
final _businessNamesProvider = FutureProvider.autoDispose
    .family<String, String>((ref, businessId) async {
      try {
        return await ref.read(apiClientProvider).fetchBusinessName(businessId);
      } catch (_) {
        return businessId;
      }
    });

class BusinessPickerScreen extends ConsumerWidget {
  const BusinessPickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(authProvider);
    final ids = switch (state) {
      AuthNeedsBusiness(:final auth) => auth.businessIds,
      AuthSignedIn(:final auth) => auth.businessIds,
      _ => const <String>[],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a shop'),
        actions: [
          TextButton(
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: ListView.separated(
        itemCount: ids.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final id = ids[i];
          final name = ref.watch(_businessNamesProvider(id));
          return ListTile(
            title: Text(name.value ?? id),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => ref.read(authProvider.notifier).chooseBusiness(id),
          );
        },
      ),
    );
  }
}
