import 'dart:typed_data';

import 'package:bloriq/postcard/echo_postcard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = EchoPostcardData(
  levelId: 3,
  moves: 12,
  bestMoves: 10,
  stars: 2,
  levelText: 'Level 3',
  movesText: 'Moves: 12',
  bestText: 'Personal best: 10',
);

void main() {
  testWidgets('PNG has exact dimensions and deterministic result art', (
    tester,
  ) async {
    final images = await tester.runAsync(
      () async => [
        await renderEchoPostcardPng(sample),
        await renderEchoPostcardPng(sample),
      ],
    );
    expect(images, isNotNull);
    final bytes = images!.first;
    expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(16), 1080);
    expect(header.getUint32(20), 1080);
    expect(images[1], orderedEquals(bytes));
  });

  testWidgets('preview exposes result and handles share errors', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EchoPostcardDialog(
            data: sample,
            title: 'Echo Postcard',
            shareLabel: 'Share image',
            closeLabel: 'Close',
            errorLabel: 'Could not share image',
            share: (png, {origin}) async => throw StateError('simulated'),
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Level 3, Moves: 12, Personal best: 10, 2/3'),
      findsOneWidget,
    );
    await tester.runAsync(() async {
      await tester.tap(find.text('Share image'));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();
    expect(find.text('Could not share image'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
