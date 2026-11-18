import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/labs_screen.dart';

void main() {
  test('a scanned report is named by its date in the app language', () {
    final when = DateTime(2026, 11, 18, 9, 5);
    expect(
      labScanFileName(when, german: false),
      'Lab scan 2026-11-18 09-05.pdf',
    );
    expect(
      labScanFileName(when, german: true),
      'Laborscan 2026-11-18 09-05.pdf',
    );
  });

  test('backing out of the scanner is not an error', () {
    expect(
      isDocumentScanCancellation(
        PlatformException(
          code: 'DocumentScanner',
          message: 'Operation cancelled',
        ),
      ),
      isTrue,
    );
    expect(
      isDocumentScanCancellation(
        PlatformException(
          code: 'DocumentScanner',
          message: 'Failed to start document scanner',
        ),
      ),
      isFalse,
    );
  });
}
