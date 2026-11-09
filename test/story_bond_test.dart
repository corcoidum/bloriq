import 'dart:convert';
import 'dart:io';

import 'package:bloriq/story/story_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _seasonJson() =>
    jsonDecode(File('assets/story/season1.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('all 25 spirits carry a bond line and promise episode in ko/en', () {
    final catalog = StoryCatalog.fromJson(_seasonJson());
    expect(catalog.spirits, hasLength(25));
    for (final spirit in catalog.spirits) {
      final line = spirit.bondLine, episode = spirit.bondEpisode;
      expect(line, isNotNull, reason: '${spirit.id} bondLine');
      expect(episode, isNotNull, reason: '${spirit.id} bondEpisode');
      for (final text in [line!, episode!]) {
        expect(text.ko.trim(), isNotEmpty, reason: spirit.id);
        expect(text.en.trim(), isNotEmpty, reason: spirit.id);
      }
      expect(
        line.ko.runes.length,
        lessThanOrEqualTo(40),
        reason: '${spirit.id} bondLine ko too long',
      );
      expect(
        episode.ko.runes.length,
        lessThanOrEqualTo(220),
        reason: '${spirit.id} bondEpisode ko too long',
      );
      expect(line.inLocale('ko'), line.ko);
      expect(episode.inLocale('en'), episode.en);
    }
  });

  test('bond texts are optional so older season data still loads', () {
    final data = _seasonJson();
    for (final spirit in data['spirits'] as List) {
      (spirit as Map<String, dynamic>)
        ..remove('bondLine')
        ..remove('bondEpisode');
    }
    final catalog = StoryCatalog.fromJson(data);
    expect(catalog.spirits, hasLength(25));
    expect(catalog.chapters, hasLength(5));
    for (final spirit in catalog.spirits) {
      expect(spirit.bondLine, isNull);
      expect(spirit.bondEpisode, isNull);
    }
  });

  test('a bond text present without both locales is rejected', () {
    final data = _seasonJson();
    ((data['spirits'] as List).first as Map<String, dynamic>)['bondLine'] = {
      'ko': '안녕',
    };
    expect(() => StoryCatalog.fromJson(data), throwsFormatException);
  });
}
