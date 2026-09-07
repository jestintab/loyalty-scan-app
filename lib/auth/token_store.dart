import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// What survives an app restart. The token is a bearer credential for a
/// business's customer records, so it lives in the Keychain / Keystore rather
/// than in SharedPreferences, which is plaintext on disk.
class StoredAuth {
  const StoredAuth({
    required this.token,
    required this.name,
    required this.role,
    required this.businessIds,
    required this.businessId,
  });

  final String token;
  final String name;
  final String role;
  final List<String> businessIds;

  /// The business chosen for this session. Null only while the picker is up.
  final String? businessId;

  StoredAuth withBusiness(String id) => StoredAuth(
        token: token,
        name: name,
        role: role,
        businessIds: businessIds,
        businessId: id,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'name': name,
        'role': role,
        'businessIds': businessIds,
        'businessId': businessId,
      };

  factory StoredAuth.fromJson(Map<String, dynamic> json) => StoredAuth(
        token: json['token'] as String,
        name: (json['name'] as String?) ?? '',
        role: (json['role'] as String?) ?? 'staff',
        businessIds: ((json['businessIds'] as List?) ?? const [])
            .map((e) => e as String)
            .toList(),
        businessId: json['businessId'] as String?,
      );
}

abstract class TokenStore {
  Future<StoredAuth?> read();
  Future<void> write(StoredAuth auth);
  Future<void> clear();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'qwallet_scan_auth';

  final FlutterSecureStorage _storage;

  @override
  Future<StoredAuth?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      return StoredAuth.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // A payload written by an older build, or corrupted. Treat it as no
      // session rather than crashing on launch, which would be unrecoverable
      // without reinstalling.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredAuth auth) =>
      _storage.write(key: _key, value: jsonEncode(auth.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());
