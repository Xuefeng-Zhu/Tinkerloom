import 'package:appnest_flutter/features/builder/builder_chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final cases = <String, String>{
    'The AI response was not valid JSON. Return exactly one complete JSON object without commentary or markdown.':
        'The AI returned a response AppNest couldn’t read.',
    'The AI response must be a JSON object, not a list or scalar.':
        'The AI returned a response AppNest couldn’t read.',
    'The AI provider returned an invalid JSON response envelope.':
        'The AI returned a response AppNest couldn’t read.',
    'AI output reached the token limit before finishing. Return a smaller complete JSON definition within 8000 tokens.':
        'The AI response ended before AppNest could finish your app.',
    'Generated definition is too large. Return a smaller complete definition.':
        'The AI response was too large for AppNest to use.',
    'The AI provider exceeded the 45-second response limit. Return a smaller complete definition.':
        'The AI service took too long to respond.',
    'AI provider could not complete the request (HTTP 503).':
        'The AI service couldn’t complete the request.',
    'Could not receive a response from the AI provider.':
        'The AI service couldn’t complete the request.',
    'The generated definition could not be validated.':
        'AppNest couldn’t validate the generated app.',
    'Generation could not validate the response.':
        'AppNest couldn’t validate the generated app.',
    'Unsupported capability: calendar.custom.v1':
        'The AI used a feature AppNest doesn’t support.',
    'Unsupported capabilities requested: calendar.custom.v1':
        'The AI used a feature AppNest doesn’t support.',
  };
  for (final entry in cases.entries) {
    test('translates ${entry.key}', () {
      final message = builderFailureMessage([entry.key], hasPreview: false);
      expect(message, '${entry.value} Try again with the same request.');
      expect(message, isNot(contains('smaller')));
      expect(message, isNot(contains('simpler')));
      expect(message, isNot(contains('Return exactly')));
    });
  }

  test(
    'unsupported feature asks to adjust features without blaming complexity',
    () {
      expect(
        builderFailureMessage([
          'This requested capability is unavailable.',
        ], hasPreview: false),
        'This request needs a feature AppNest doesn’t support yet. Adjust the requested features, then try again.',
      );
    },
  );

  test('unknown details are not reflected into the main message', () {
    expect(
      builderFailureMessage([
        'Unexpected diagnostic containing internal values.',
      ], hasPreview: false),
      'AppNest couldn’t finish building this preview. Try again with the same request.',
    );
    expect(
      builderFailureMessage([], hasPreview: false),
      'AppNest couldn’t finish building this preview. Try again with the same request.',
    );
  });

  test('failed edits explicitly preserve the last preview', () {
    expect(
      builderFailureMessage([
        'The AI response was not valid JSON.',
      ], hasPreview: true),
      'The AI returned a response AppNest couldn’t read. Your last preview is still here. Try again with the same request.',
    );
  });
}
