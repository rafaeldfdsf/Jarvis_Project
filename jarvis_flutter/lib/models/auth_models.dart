class AuthUserModel {
  const AuthUserModel({
    required this.id,
    required this.email,
    required this.displayName,
    required this.createdAt,
    required this.emailVerified,
    this.emailVerifiedAt,
  });

  final String id;
  final String email;
  final String displayName;
  final String createdAt;
  final bool emailVerified;
  final String? emailVerifiedAt;

  factory AuthUserModel.fromJson(Map<String, dynamic> json) {
    return AuthUserModel(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      emailVerified: json['email_verified'] == true,
      emailVerifiedAt: json['email_verified_at']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'created_at': createdAt,
      'email_verified': emailVerified,
      'email_verified_at': emailVerifiedAt,
    };
  }
}

class AuthSessionModel {
  const AuthSessionModel({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final AuthUserModel user;

  factory AuthSessionModel.fromJson(Map<String, dynamic> json) {
    return AuthSessionModel(
      accessToken: json['access_token']?.toString() ?? '',
      tokenType: json['token_type']?.toString() ?? 'bearer',
      user: AuthUserModel.fromJson(
        (json['user'] as Map<String, dynamic>? ?? <String, dynamic>{}),
      ),
    );
  }
}

class AuthStatusModel {
  const AuthStatusModel({
    required this.ok,
    required this.message,
    required this.email,
    required this.emailSent,
    required this.verificationRequired,
  });

  final bool ok;
  final String message;
  final String email;
  final bool emailSent;
  final bool verificationRequired;

  factory AuthStatusModel.fromJson(Map<String, dynamic> json) {
    return AuthStatusModel(
      ok: json['ok'] != false,
      message: json['message']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      emailSent: json['email_sent'] == true,
      verificationRequired: json['verification_required'] == true,
    );
  }
}
