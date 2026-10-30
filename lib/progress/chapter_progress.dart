import '../domain/puzzle.dart';
import 'progress_repository.dart';

class ChapterProgress {
  ChapterProgress(this.number, this.levels, this.repository);
  final int number;
  final List<Level> levels;
  final ProgressRepository repository;
  int get completed => levels
      .where(
        (level) =>
            repository.forLevel(level.id, revision: level.revision) != null,
      )
      .length;
  int get stars => levels.fold(
    0,
    (total, level) =>
        total +
        (repository.forLevel(level.id, revision: level.revision)?.bestStars ??
            0),
  );
  int get recommendedLevelId => levels
      .firstWhere(
        (level) =>
            repository.forLevel(level.id, revision: level.revision) == null,
        orElse: () => levels.first,
      )
      .id;
  static List<ChapterProgress> group(
    List<Level> levels,
    ProgressRepository repository,
  ) => [
    for (var offset = 0; offset < levels.length; offset += 5)
      ChapterProgress(
        offset ~/ 5 + 1,
        levels.skip(offset).take(5).toList(),
        repository,
      ),
  ];
}
