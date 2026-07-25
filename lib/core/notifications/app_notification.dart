class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.priority,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.entityRef = const {},
    this.mosqueId,
  });

  final String id;
  final String type;
  final String priority;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, dynamic> entityRef;
  final String? mosqueId;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      priority: json['priority']?.toString() ?? 'informational',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readAt: json['read_at'] != null
          ? DateTime.tryParse(json['read_at'].toString())
          : null,
      entityRef: json['entity_ref'] is Map
          ? Map<String, dynamic>.from(json['entity_ref'] as Map)
          : const {},
      mosqueId: json['mosque_id']?.toString(),
    );
  }

  String get typeLabelAr => switch (type) {
        'mosque_registration_request' => 'طلب تسجيل مسجد',
        'mosque_registration_approved' => 'اعتماد التسجيل',
        'mosque_registration_rejected' => 'رفض التسجيل',
        'registration_sms_failed' => 'فشل إرسال الرمز',
        'homework_updated' => 'واجب',
        'no_attendance_today' => 'لا حضور اليوم',
        'teacher_joined' => 'مدرّس جديد',
        'sync_pending' => 'مزامنة معلّقة',
        _ => type,
      };
}
