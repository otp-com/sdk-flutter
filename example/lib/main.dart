import 'package:flutter/material.dart';
import 'package:otp_flutter/otp_flutter.dart';

void main() {
  runApp(const OtpExampleApp());
}

class OtpExampleApp extends StatelessWidget {
  const OtpExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: OtpExampleScreen());
  }
}

/// A menu in front of the bridge, so each call can be made on a device.
///
/// Nothing here is part of the package. It is the app a customer would write, and it uses only
/// what a customer can see.
class OtpExampleScreen extends StatefulWidget {
  const OtpExampleScreen({super.key});

  @override
  State<OtpExampleScreen> createState() => _OtpExampleScreenState();
}

class _OtpExampleScreenState extends State<OtpExampleScreen> {
  final _publishableKeyController = TextEditingController(
    text: 'otp_pk_test_…',
  );
  final _recipientController = TextEditingController(text: '+14155552671');
  final _codeController = TextEditingController();

  PendingOtp? _pending;
  String _outcome = '';

  Future<void> _report(String label, Future<Object?> Function() call) async {
    setState(() => _outcome = '$label…');
    try {
      final result = await call();
      setState(() => _outcome = '$label: $result');
    } on OtpException catch (error) {
      // Every call in the package throws this and nothing else, which is what makes a screen
      // like this able to branch rather than guess.
      setState(() {
        _outcome =
            '$label failed: ${error.kind.name}'
            '${error.type != null ? ' (${error.type})' : ''}'
            '${error.retryAfterSeconds != null ? ', retry after ${error.retryAfterSeconds}s' : ''}'
            '\n${error.message}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('otp.com bridge')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'publishable key',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            TextField(controller: _publishableKeyController),
            const Text(
              'recipient',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            TextField(controller: _recipientController),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _report(
                'configure',
                () => Otp.configure(
                  publishableKey: _publishableKeyController.text,
                ),
              ),
              child: const Text('configure'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Presented screens',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: () => _report(
                'verify',
                () => Otp.verify(_recipientController.text, locale: 'en'),
              ),
              child: const Text('verify'),
            ),
            ElevatedButton(
              onPressed: () => _report(
                'verifyCollecting',
                () => Otp.verifyCollecting(RecipientKind.phone, locale: 'en'),
              ),
              child: const Text('verify, collecting a phone number'),
            ),
            ElevatedButton(
              onPressed: () => _report(
                'verifyCollecting',
                () => Otp.verifyCollecting(RecipientKind.email, locale: 'en'),
              ),
              child: const Text('verify, collecting an email address'),
            ),
            ElevatedButton(
              onPressed: () =>
                  _report('resumeInterrupted', () => Otp.resumeInterrupted()),
              child: const Text('resume an interrupted verification'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your own screen',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            ElevatedButton(
              onPressed: () => _report('start', () async {
                final started = await Otp.start(
                  _recipientController.text,
                  locale: 'en',
                );
                setState(() => _pending = started);
                return started;
              }),
              child: const Text('start'),
            ),
            Text(
              'code${_pending != null ? ' (${_pending!.codeLength} digits)' : ''}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
            ),
            ElevatedButton(
              onPressed: () => _report(
                'submit',
                () => Otp.submit(_pending?.id ?? '', _codeController.text),
              ),
              child: const Text('submit'),
            ),
            ElevatedButton(
              onPressed: () =>
                  _report('resend', () => Otp.resend(_pending?.id ?? '')),
              child: const Text('resend'),
            ),
            ElevatedButton(
              onPressed: () =>
                  _report('resume', () => Otp.resume(_pending?.id ?? '')),
              child: const Text('resume'),
            ),
            ElevatedButton(
              onPressed: () => _report('interrupted', () => Otp.interrupted()),
              child: const Text('what is in flight'),
            ),
            const SizedBox(height: 20),
            Text(
              _outcome,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
