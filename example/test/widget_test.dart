import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otp_flutter_example/main.dart';

void main() {
  testWidgets('shows the bridge menu', (WidgetTester tester) async {
    await tester.pumpWidget(const OtpExampleApp());

    expect(find.text('otp.com bridge'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, 'configure'), findsOneWidget);
  });
}
