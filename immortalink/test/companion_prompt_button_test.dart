import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immortalink/widgets/companion_prompt_button.dart';

void main() {
  for (final width in [280.0, 390.0, 768.0]) {
    testWidgets('full prompt wraps at width $width with enlarged text', (tester) async {
      const prompt = 'Can you share more about your favourite memories from your visit to the mountains with your family and friends?';
      String? selected;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
        child: Align(alignment: Alignment.topLeft, child: SizedBox(
          width: width,
          child: Wrap(children: [CompanionPromptButton(
            text: prompt, onPressed: () => selected = prompt,
          )]),
        )),
      ))));
      final paragraph = tester.renderObject<RenderParagraph>(find.text(prompt));
      expect(paragraph.didExceedMaxLines, false);
      expect(paragraph.size.width, lessThan(width));
      expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThan(48));
      await tester.tap(find.text(prompt));
      expect(selected, prompt);
      expect(tester.takeException(), null);
    });
  }
}
