/// お迎え者マスタ(202)。fetch_pickup_persons_for_child の1行。
class PickupPerson {
  const PickupPerson({
    required this.personId,
    required this.name,
    this.relationship,
    this.phone,
    required this.hasDocument,
    required this.idVerified,
  });

  final String personId;
  final String name;
  final String? relationship;
  final String? phone;
  final bool hasDocument;
  final bool idVerified;

  factory PickupPerson.fromJson(Map<String, dynamic> json) => PickupPerson(
        personId: json['person_id'] as String,
        name: json['name'] as String,
        relationship: json['relationship'] as String?,
        phone: json['phone'] as String?,
        hasDocument: json['has_document'] as bool? ?? false,
        idVerified: json['id_verified'] as bool? ?? false,
      );
}
