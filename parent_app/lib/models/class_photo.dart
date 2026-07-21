/// 公開済みのクラス写真(class_daily_photos)。
class ClassPhoto {
  const ClassPhoto({
    required this.id,
    required this.businessDate,
    required this.storagePath,
  });

  factory ClassPhoto.fromJson(Map<String, dynamic> json) => ClassPhoto(
        id: json['id'] as String,
        businessDate: DateTime.parse(json['business_date'] as String),
        storagePath: json['storage_path'] as String,
      );

  final String id;
  final DateTime businessDate;
  final String storagePath;
}
