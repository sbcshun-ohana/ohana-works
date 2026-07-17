/// ログイン中保護者自身のプロフィール(guardiansテーブルの自分の行)。
class GuardianProfile {
  const GuardianProfile({
    required this.id,
    required this.name,
    this.nameKana,
    this.phone,
    this.email,
    required this.status,
  });

  factory GuardianProfile.fromJson(Map<String, dynamic> json) => GuardianProfile(
        id: json['id'] as String,
        name: json['name'] as String,
        nameKana: json['name_kana'] as String?,
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        status: json['status'] as String,
      );

  final String id;
  final String name;
  final String? nameKana;
  final String? phone;
  final String? email;
  final String status;

  bool get isActive => status == 'active';
}
