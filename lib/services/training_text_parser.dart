
class DraftSet {
  final double? weight;
  final int? reps;
  final double? percentage;
  final double? rpe;
  final double? rir;
  final String scheme;
  const DraftSet({this.weight, this.reps, this.percentage, this.rpe, this.rir, this.scheme = ''});
  static DraftProgram fromAiJson(Map<String, dynamic> json) {
    final weeks = <DraftWeek>[];
    final rawWeeks = (json['weeks'] as List?) ?? const [];
    for (final rawWeek in rawWeeks) {
      final w = Map<String, dynamic>.from(rawWeek as Map);
      final days = <DraftDay>[];
      final rawDays = (w['days'] as List?) ?? const [];
      for (final rawDay in rawDays) {
        final d = Map<String, dynamic>.from(rawDay as Map);
        final exercises = <DraftExercise>[];
        final rawExercises = (d['exercises'] as List?) ?? const [];
        for (final rawExercise in rawExercises) {
          final e = Map<String, dynamic>.from(rawExercise as Map);
          final sets = <DraftSet>[];
          final rawSets = (e['sets'] as List?) ?? const [];
          for (final rawSet in rawSets) {
            final s = Map<String, dynamic>.from(rawSet as Map);
            sets.add(DraftSet(
              weight: (s['weight'] as num?)?.toDouble(),
              reps: (s['reps'] as num?)?.toInt(),
              percentage: (s['percentage'] as num?)?.toDouble(),
              rpe: (s['rpe'] as num?)?.toDouble(),
              rir: (s['rir'] as num?)?.toDouble(),
              scheme: (s['scheme'] ?? '').toString(),
            ));
          }
          exercises.add(DraftExercise(
            (e['name'] ?? 'Неизвестное упражнение').toString(),
            sets,
          ));
        }
        days.add(DraftDay((d['name'] ?? 'Тренировка').toString(), exercises));
      }
      weeks.add(DraftWeek(
        (w['number'] as num?)?.toInt() ?? weeks.length + 1,
        days,
      ));
    }
    final clarifications=<DraftClarification>[];
    for(final raw in (json['clarifications'] as List? ?? const [])){
      if(raw is! Map) continue;
      final m=Map<String,dynamic>.from(raw);
      clarifications.add(DraftClarification(
        id:(m['id']??clarifications.length+1).toString(),
        question:(m['question']??'Уточните, что имеется в виду.').toString(),
        context:(m['context']??'').toString(),
        options:(m['options'] as List? ?? const []).map((e)=>e.toString()).toList(),
      ));
    }
    return DraftProgram(
      name: (json['name'] ?? 'AI программа').toString(),
      weeks: weeks.isEmpty ? [DraftWeek(1, [DraftDay('Тренировка 1', [])])] : weeks,
      warnings: (json['warnings'] as List? ?? const []).map((e) => e.toString()).toList(),
      missingData: (json['missing_data'] as List? ?? const []).map((e) => e.toString()).toList(),
      clarifications: clarifications,
    );
  }
}

class DraftExercise {
  final String name;
  final List<DraftSet> sets;
  DraftExercise(this.name, this.sets);
}

class DraftDay {
  final String name;
  final List<DraftExercise> exercises;
  DraftDay(this.name, this.exercises);
}

class DraftWeek {
  final int number;
  final List<DraftDay> days;
  DraftWeek(this.number, this.days);
}

class DraftClarification {
  final String id;
  final String question;
  final String context;
  final List<String> options;
  const DraftClarification({required this.id, required this.question, this.context = '', this.options = const []});
}

class DraftProgram {
  final String name;
  final List<DraftWeek> weeks;
  final List<String> warnings;
  final List<String> missingData;
  final List<DraftClarification> clarifications;
  DraftProgram({required this.name, required this.weeks, this.warnings = const [], this.missingData = const [], this.clarifications = const []});
}

class TrainingTextParser {
  static final _week = RegExp(r'^\s*(?:неделя|week)\s*[-#:]*\s*(\d+)', caseSensitive: false);
  static final _day = RegExp(r'^\s*(?:день|тренировка|day|workout)\s*[-#:]*\s*(\d+)?\s*(.*)$', caseSensitive: false);
  static final _setsRe = RegExp(r'(\d+)\s*[xх×]\s*(\d+|amrap)', caseSensitive: false);
  static final _weightRe = RegExp(r'(\d+(?:[.,]\d+)?)\s*(?:кг|kg)\b', caseSensitive: false);
  static final _pctRe = RegExp(r'@\s*(\d+(?:[.,]\d+)?)\s*%');
  static final _rpeRe = RegExp(r'\bRPE\s*(?:=|:)?\s*(\d+(?:[.,]\d+)?)', caseSensitive: false);
  static final _rirRe = RegExp(r'\bRIR\s*(?:=|:)?\s*(\d+(?:[.,]\d+)?)', caseSensitive: false);

  static DraftProgram parse(String source, {String? name}) {
    var weeks = <DraftWeek>[];
    var currentWeek = DraftWeek(1, []);
    var currentDay = DraftDay('Тренировка 1', []);
    var dayCounter = 1;
    final warnings = <String>[];
    final missing = <String>[];

    void flushDay() {
      if (currentDay.exercises.isNotEmpty && !currentWeek.days.contains(currentDay)) {
        currentWeek.days.add(currentDay);
      }
    }
    void flushWeek() {
      flushDay();
      if (currentWeek.days.isNotEmpty) weeks.add(currentWeek);
    }
    void ensureDay() {
      if (currentWeek.days.isEmpty && currentDay.exercises.isEmpty) {
        currentDay = DraftDay('Тренировка ' + dayCounter.toString(), []);
        dayCounter++;
      }
    }

    for (final raw in source.split(RegExp(r'\r?\n'))) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final wm = _week.firstMatch(line);
      if (wm != null) {
        flushWeek();
        final n = int.tryParse(wm.group(1) ?? '') ?? (weeks.length + 1);
        currentWeek = DraftWeek(n, []);
        currentDay = DraftDay('Тренировка 1', []);
        dayCounter = 1;
        continue;
      }
      final dm = _day.firstMatch(line);
      if (dm != null && !line.contains(RegExp(r'\d+\s*[xх×]\s*\d+', caseSensitive: false))) {
        flushDay();
        final tail = (dm.group(2) ?? '').trim();
        final number = dm.group(1);
        currentDay = DraftDay(
          tail.isEmpty ? 'Тренировка ' + (number ?? dayCounter.toString()) : tail,
          [],
        );
        dayCounter++;
        continue;
      }
      ensureDay();
      final sm = _setsRe.firstMatch(line);
      if (sm == null) {
        warnings.add('Не распознана схема подходов: «' + line + '»');
        currentDay.exercises.add(DraftExercise(line, const []));
        continue;
      }
      final count = int.tryParse(sm.group(1)!) ?? 1;
      final repsToken = sm.group(2)!;
      final reps = repsToken.toLowerCase() == 'amrap' ? null : int.tryParse(repsToken);
      final wm2 = _weightRe.firstMatch(line);
      final pm = _pctRe.firstMatch(line);
      final rm = _rpeRe.firstMatch(line);
      final rim = _rirRe.firstMatch(line);
      final weight = wm2 == null ? null : double.tryParse(wm2.group(1)!.replaceAll(',', '.'));
      final pct = pm == null ? null : double.tryParse(pm.group(1)!.replaceAll(',', '.'));
      final rpe = rm == null ? null : double.tryParse(rm.group(1)!.replaceAll(',', '.'));
      final rir = rim == null ? null : double.tryParse(rim.group(1)!.replaceAll(',', '.'));
      var exerciseName = line.substring(0, sm.start).trim();
      exerciseName = exerciseName.replaceAll(_weightRe, '').replaceAll(RegExp(r'[-:]+$'), '').trim();
      if (exerciseName.isEmpty) {
        exerciseName = 'Неизвестное упражнение';
        warnings.add('Не удалось определить упражнение: «' + line + '»');
      }
      final draftSets = List.generate(count, (_) => DraftSet(
        weight: weight, reps: reps, percentage: pct, rpe: rpe, rir: rir, scheme: reps == null ? 'AMRAP' : '',
      ));
      final existing = currentDay.exercises.indexWhere((e) => e.name.toLowerCase() == exerciseName.toLowerCase());
      if (existing >= 0) {
        currentDay.exercises[existing].sets.addAll(draftSets);
      } else {
        currentDay.exercises.add(DraftExercise(exerciseName, draftSets));
      }
      if (weight == null && pct == null) missing.add(exerciseName + ': отсутствует вес или процент 1ПМ');
    }
    flushWeek();
    if (weeks.isEmpty) {
      weeks = [DraftWeek(1, [DraftDay('Тренировка 1', [])])];
      warnings.add('Из текста не удалось собрать структуру недели; создан пустой шаблон.');
    }
    return DraftProgram(
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'Импортированная программа',
      weeks: weeks, warnings: warnings, missingData: missing,
    );
  }

  static DraftProgram fromAiJson(Map<String, dynamic> json) {
    final weeks = <DraftWeek>[];
    final rawWeeks = (json['weeks'] as List?) ?? const [];
    for (final rawWeek in rawWeeks) {
      final w = Map<String, dynamic>.from(rawWeek as Map);
      final days = <DraftDay>[];
      final rawDays = (w['days'] as List?) ?? const [];
      for (final rawDay in rawDays) {
        final d = Map<String, dynamic>.from(rawDay as Map);
        final exercises = <DraftExercise>[];
        final rawExercises = (d['exercises'] as List?) ?? const [];
        for (final rawExercise in rawExercises) {
          final e = Map<String, dynamic>.from(rawExercise as Map);
          final sets = <DraftSet>[];
          final rawSets = (e['sets'] as List?) ?? const [];
          for (final rawSet in rawSets) {
            final s = Map<String, dynamic>.from(rawSet as Map);
            sets.add(DraftSet(
              weight: (s['weight'] as num?)?.toDouble(),
              reps: (s['reps'] as num?)?.toInt(),
              percentage: (s['percentage'] as num?)?.toDouble(),
              rpe: (s['rpe'] as num?)?.toDouble(),
              rir: (s['rir'] as num?)?.toDouble(),
              scheme: (s['scheme'] ?? '').toString(),
            ));
          }
          exercises.add(DraftExercise((e['name'] ?? 'Неизвестное упражнение').toString(), sets));
        }
        days.add(DraftDay((d['name'] ?? 'Тренировка').toString(), exercises));
      }
      weeks.add(DraftWeek((w['number'] as num?)?.toInt() ?? weeks.length + 1, days));
    }
    return DraftProgram(
      name: (json['name'] ?? 'AI программа').toString(),
      weeks: weeks.isEmpty ? [DraftWeek(1, [DraftDay('Тренировка 1', [])])] : weeks,
      warnings: (json['warnings'] as List? ?? const []).map((e) => e.toString()).toList(),
      missingData: (json['missing_data'] as List? ?? const []).map((e) => e.toString()).toList(),
    );
  }

}
