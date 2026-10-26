import 'package:aroll_mobile/data/owner_support_email.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile support request matches the website body', () {
    expect(
      ownerSupportEmailRequest(
        subject: ' Scanner ',
        message: ' The page is blank. ',
      ),
      {
        'subject': 'Scanner',
        'message': 'The page is blank.',
      },
    );
  });

  test('the request cannot select a recipient', () {
    final body = ownerSupportEmailRequest(
      subject: 'Help',
      message: 'Need help',
    );
    expect(body.keys, ['subject', 'message']);
    expect(body.containsKey('recipient'), isFalse);
    expect(body.containsKey('to'), isFalse);
  });

  test('blank, injected, and oversized drafts are rejected', () {
    expect(ownerSupportDraftError('  ', 'Need help'), 'Enter a subject.');
    expect(
      ownerSupportDraftError('Hello\nBcc: evil@example.com', 'Need help'),
      'Subject cannot contain line breaks.',
    );
    expect(
      ownerSupportDraftError('Hello', 'x' * (ownerSupportMessageMax + 1)),
      'Message must be $ownerSupportMessageMax characters or less.',
    );
  });
}
