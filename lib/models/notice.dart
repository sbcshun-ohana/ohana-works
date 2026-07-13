/// 8章 職員連絡(お知らせ)。
class Notice {
  const Notice({
    required this.id,
    required this.category,
    required this.title,
    required this.body,
    required this.requiresReadConfirmation,
    required this.standardReplyOptions,
    required this.createdAt,
    this.targetOfficeId,
    this.targetPositionId,
    this.myReadAt,
    this.myReplyOption,
  });

  factory Notice.fromJson(Map<String, dynamic> json) {
    // notice_recipients は自分の既読行のみRLSで見える(0件 or 1件)ため先頭を採用する。
    final recipientRows = (json['notice_recipients'] as List?) ?? const [];
    final myRecipient = recipientRows.isNotEmpty
        ? recipientRows.first as Map<String, dynamic>
        : null;

    return Notice(
      id: json['id'] as String,
      category: json['category'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      requiresReadConfirmation: json['requires_read_confirmation'] as bool,
      standardReplyOptions:
          (json['standard_reply_options'] as List?)?.cast<String>() ??
              const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      targetOfficeId: json['target_office_id'] as String?,
      targetPositionId: json['target_position_id'] as String?,
      myReadAt: myRecipient?['read_at'] != null
          ? DateTime.parse(myRecipient!['read_at'] as String)
          : null,
      myReplyOption: myRecipient?['reply_option'] as String?,
    );
  }

  final String id;
  final String category;
  final String title;
  final String body;
  final bool requiresReadConfirmation;
  final List<String> standardReplyOptions;
  final DateTime createdAt;
  final String? targetOfficeId;
  final String? targetPositionId;
  final DateTime? myReadAt;
  final String? myReplyOption;

  bool get isRead => myReadAt != null;
}

class NoticeAttachment {
  const NoticeAttachment({
    required this.id,
    required this.filePath,
    required this.fileName,
    this.contentType,
  });

  factory NoticeAttachment.fromJson(Map<String, dynamic> json) {
    return NoticeAttachment(
      id: json['id'] as String,
      filePath: json['file_path'] as String,
      fileName: json['file_name'] as String,
      contentType: json['content_type'] as String?,
    );
  }

  final String id;
  final String filePath;
  final String fileName;
  final String? contentType;
}

/// 管理者モード: お知らせ対象者ごとの既読状況。
class NoticeAudienceEntry {
  const NoticeAudienceEntry({required this.employeeName, this.readAt});

  final String employeeName;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}
