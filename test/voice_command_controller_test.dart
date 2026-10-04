import 'package:flutter_test/flutter_test.dart';
import 'package:visionpath/services/voice_command_controller.dart';

void main() {
  group('VoiceCommandFailure classification', () {
    test('permission problems are told apart from silence', () {
      // The two failures need very different sentences, so they must never be
      // collapsed into one flag.
      expect(
        VoiceCommandController.isPermissionProblem(
          VoiceCommandFailure.permissionDenied,
        ),
        isTrue,
      );
      expect(
        VoiceCommandController.isPermissionProblem(
          VoiceCommandFailure.nothingHeard,
        ),
        isFalse,
      );
    });

    test('every failure has a spoken explanation', () {
      // Part 19 requires audio feedback for both, so neither message may be
      // blank.
      expect(
        VoiceCommandController.permissionDeniedMessage,
        'Microphone permission is required for voice commands.',
      );
      expect(
        VoiceCommandController.nothingHeardMessage,
        "Sorry, I didn't hear that.",
      );
    });
  });

  group('hold gesture contract', () {
    test('a short tap can never open the assistant', () {
      // The threshold is what separates "hold to speak" from "tap the screen",
      // so it has to be long enough to be deliberate.
      expect(
        VoiceCommandController.holdThreshold,
        greaterThan(const Duration(milliseconds: 200)),
      );
      expect(
        VoiceCommandController.holdThreshold,
        lessThan(const Duration(seconds: 1)),
      );
    });

    test('a fresh controller is idle and silent', () {
      final VoiceCommandController controller = VoiceCommandController();
      addTearDown(controller.dispose);

      expect(controller.isHolding, isFalse);
      expect(controller.isListening, isFalse);
      // The overlay is driven by isActive, so it must start hidden.
      expect(controller.isActive, isFalse);
      expect(controller.transcript, isEmpty);
      expect(controller.failure, isNull);
    });

    test('state is reported separately from the overlay visibility', () {
      final VoiceCommandController controller = VoiceCommandController();
      addTearDown(controller.dispose);

      int notifications = 0;
      controller.addListener(() => notifications++);

      // Nothing to assert about the microphone here (it needs a real engine),
      // but the controller must never claim to listen before a hold starts.
      expect(controller.isListening, isFalse);
      expect(notifications, 0);
    });
  });
}