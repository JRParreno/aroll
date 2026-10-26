const ownerSupportSubjectMax = 120;
const ownerSupportMessageMax = 4000;

/// Website and mobile both post this shape to `/owner/support-email`.
/// The server chooses the recipient.
Map<String, String> ownerSupportEmailRequest({
  required String subject,
  required String message,
}) {
  final cleanSubject = subject.trim();
  final cleanMessage = message.trim();
  final error = ownerSupportDraftError(cleanSubject, cleanMessage);
  if (error != null) {
    throw ArgumentError(error);
  }
  return {
    'subject': cleanSubject,
    'message': cleanMessage,
  };
}

String ownerHelpFailureMessage(Object error) {
  final detail = _errorDetail(error);
  if (detail != null &&
      detail.trim().isNotEmpty &&
      detail.trim().length <= 300 &&
      !RegExp(r'traceback|password|exception', caseSensitive: false)
          .hasMatch(detail)) {
    return detail.trim();
  }
  return 'The support message could not be sent. Try again in a moment.';
}

String? _errorDetail(Object error) {
  try {
    final dynamic value = error;
    final data = value.response?.data;
    if (data is Map && data['detail'] is String) {
      return data['detail'] as String;
    }
  } catch (_) {}
  return null;
}

String? ownerSupportDraftError(String subject, String message) {
  final cleanSubject = subject.trim();
  final cleanMessage = message.trim();
  if (cleanSubject.isEmpty) return 'Enter a subject.';
  if (cleanSubject.length > ownerSupportSubjectMax) {
    return 'Subject must be $ownerSupportSubjectMax characters or less.';
  }
  if (cleanSubject.contains('\n') || cleanSubject.contains('\r')) {
    return 'Subject cannot contain line breaks.';
  }
  if (cleanMessage.isEmpty) return 'Enter the concern or message.';
  if (cleanMessage.length > ownerSupportMessageMax) {
    return 'Message must be $ownerSupportMessageMax characters or less.';
  }
  return null;
}
