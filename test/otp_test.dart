// Mocks the platform channel directly, one handler per Pigeon method, because this contract has
// no `@FlutterApi` counterpart for Pigeon's `dartTestOut` to generate a mock for.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otp_flutter/otp_flutter.dart';
import 'package:otp_flutter/src/messages.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockMethod(String method, Object? Function(List<Object?> args) handler) {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.otp_flutter.OtpHostApi.$method',
      OtpHostApi.pigeonChannelCodec,
    );
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      final args = message as List<Object?>;
      return <Object?>[handler(args)];
    });
  }

  void mockMethodThrowing(String method, PlatformException error) {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.otp_flutter.OtpHostApi.$method',
      OtpHostApi.pigeonChannelCodec,
    );
    messenger.setMockDecodedMessageHandler<Object?>(channel, (message) async {
      return <Object?>[error.code, error.message, error.details];
    });
  }

  tearDown(() {
    for (final method in [
      'configure',
      'verify',
      'verifyCollecting',
      'resumeInterrupted',
      'start',
      'submit',
      'resend',
      'resume',
      'interrupted',
    ]) {
      messenger.setMockDecodedMessageHandler<Object?>(
        BasicMessageChannel<Object?>(
          'dev.flutter.pigeon.otp_flutter.OtpHostApi.$method',
          OtpHostApi.pigeonChannelCodec,
        ),
        null,
      );
    }
  });

  PendingOtpMessage pendingMessage({
    String status = 'pending',
    String? channel,
    String? resendAvailableAt,
  }) => PendingOtpMessage(
    id: 'otp_1',
    status: status,
    channel: channel,
    maskedRecipient: '+1******89',
    codeLength: 6,
    expiresAt: '2026-09-18T12:00:00Z',
    resendAvailableAt: resendAvailableAt,
    handoffUrl: null,
  );

  test('an unknown channel string arrives as OtpChannel.unknown', () async {
    mockMethod('start', (_) => pendingMessage(channel: 'carrier_pigeon'));
    final pending = await Otp.start('+15555550123');
    expect(pending.channel, OtpChannel.unknown);
  });

  test('an unknown status string arrives as OtpStatus.unknown', () async {
    mockMethod('start', (_) => pendingMessage(status: 'stuck'));
    final pending = await Otp.start('+15555550123');
    expect(pending.status, OtpStatus.unknown);
  });

  test('expiresAt and resendAvailableAt parse to the right DateTime', () async {
    mockMethod('start', (_) => pendingMessage(resendAvailableAt: '2026-09-18T12:05:00Z'));
    final pending = await Otp.start('+15555550123');
    expect(pending.expiresAt, DateTime.utc(2026, 9, 18, 12));
    expect(pending.resendAvailableAt, DateTime.utc(2026, 9, 18, 12, 5));
  });

  test('a null resendAvailableAt stays null', () async {
    mockMethod('start', (_) => pendingMessage());
    final pending = await Otp.start('+15555550123');
    expect(pending.resendAvailableAt, isNull);
  });

  test('submit with a verification produces CodeMatched', () async {
    mockMethod(
      'submit',
      (_) => CodeSubmissionMessage(
        verification: VerificationMessage(
          otpId: 'otp_1',
          token: 'tok_1',
          tokenExpiresAt: '2026-09-18T12:10:00Z',
        ),
      ),
    );
    final result = await Otp.submit('otp_1', '123456');
    expect(result, isA<CodeMatched>());
    expect((result as CodeMatched).verification.token, 'tok_1');
  });

  test('submit without a verification produces CodeRejected with details', () async {
    mockMethod(
      'submit',
      (_) => CodeSubmissionMessage(attemptsRemaining: 2, reason: 'incorrectCode'),
    );
    final result = await Otp.submit('otp_1', '000000');
    expect(result, isA<CodeRejected>());
    final rejected = result as CodeRejected;
    expect(rejected.attemptsRemaining, 2);
    expect(rejected.reason, RejectionReason.incorrectCode);
  });

  test(
    'a PlatformException with code rateLimited becomes an OtpException with its fields',
    () async {
      mockMethodThrowing(
        'start',
        PlatformException(
          code: 'rateLimited',
          message: 'too many attempts',
          details: {'type': 'otp_rate_limited', 'statusCode': 429, 'retryAfterSeconds': 30},
        ),
      );
      try {
        await Otp.start('+15555550123');
        fail('expected an OtpException');
      } on OtpException catch (error) {
        expect(error.kind, OtpErrorKind.rateLimited);
        expect(error.type, 'otp_rate_limited');
        expect(error.statusCode, 429);
        expect(error.retryAfterSeconds, 30);
      }
    },
  );

  test('a PlatformException with an unrecognised code becomes OtpErrorKind.unknown', () async {
    mockMethodThrowing('start', PlatformException(code: 'somethingNew', message: 'nope'));
    try {
      await Otp.start('+15555550123');
      fail('expected an OtpException');
    } on OtpException catch (error) {
      expect(error.kind, OtpErrorKind.unknown);
    }
  });

  test(
    'resend with OtpChannel.unknown throws validationFailed and never reaches the host',
    () async {
      var called = false;
      mockMethod('resend', (_) {
        called = true;
        return pendingMessage();
      });
      try {
        await Otp.resend('otp_1', channel: OtpChannel.unknown);
        fail('expected an OtpException');
      } on OtpException catch (error) {
        expect(error.kind, OtpErrorKind.validationFailed);
      }
      expect(called, isFalse);
    },
  );
}
