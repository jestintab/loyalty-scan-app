/// A signed-in user plus the token that authenticates them.
class Session {
  const Session({
    required this.token,
    required this.userId,
    required this.email,
    required this.name,
    required this.role,
    required this.businessIds,
  });

  final String token;
  final int userId;
  final String? email;
  final String name;

  /// 'admin', 'business', 'staff' or 'customer'. The last cannot use this app —
  /// AuthNotifier refuses it before the token is stored.
  final String role;

  /// Every business this user may act on. Empty is a real state: an owner can
  /// unlink a staff member from their last shop.
  final List<String> businessIds;

  factory Session.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map).cast<String, dynamic>();
    return Session(
      token: json['token'] as String,
      userId: user['id'] as int,
      email: user['email'] as String?,
      name: (user['name'] as String?) ?? '',
      role: user['role'] as String,
      businessIds: ((user['businessIds'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
    );
  }
}
