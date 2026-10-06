import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:math';

final databaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError(),
);

class AppDatabase {
  late Database db;

  Future<void> init() async {
    db = await openDatabase(
      join(await getDatabasesPath(), 'my_workout_diary.db'),
      version: 3,
      onCreate: (d, _) => _createSchema(d),
      onUpgrade: (d, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await d.execute('ALTER TABLE planned_sets ADD COLUMN percentage REAL');
        }
        if (oldVersion < 3) {
          await d.execute('ALTER TABLE planned_sets ADD COLUMN scheme TEXT');
        }
      },
    );
    await createDemoCycleIfNeeded();
  }

  Future<void> _createSchema(Database d) async {
    await d.execute('CREATE TABLE cycles(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,weeks INTEGER NOT NULL,created_at TEXT NOT NULL)');
    await d.execute('CREATE TABLE weeks(id INTEGER PRIMARY KEY AUTOINCREMENT,cycle_id INTEGER NOT NULL,week_no INTEGER NOT NULL)');
    await d.execute('CREATE TABLE days(id INTEGER PRIMARY KEY AUTOINCREMENT,week_id INTEGER NOT NULL,day_no INTEGER NOT NULL,name TEXT)');
    await d.execute('CREATE TABLE exercises(id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT UNIQUE,category TEXT,unit TEXT DEFAULT "kg")');
    await d.execute('CREATE TABLE workouts(id INTEGER PRIMARY KEY AUTOINCREMENT,day_id INTEGER,cycle_id INTEGER,status TEXT DEFAULT "planned",started_at TEXT,finished_at TEXT,duration_sec INTEGER DEFAULT 0)');
    await d.execute('CREATE TABLE workout_exercises(id INTEGER PRIMARY KEY AUTOINCREMENT,workout_id INTEGER,exercise_id INTEGER,sort_no INTEGER)');
    await d.execute('CREATE TABLE planned_sets(id INTEGER PRIMARY KEY AUTOINCREMENT,workout_exercise_id INTEGER,set_no INTEGER,weight REAL,reps INTEGER,percentage REAL,rpe REAL,rir REAL,scheme TEXT)');
    await d.execute('CREATE TABLE actual_sets(id INTEGER PRIMARY KEY AUTOINCREMENT,planned_set_id INTEGER,weight REAL,reps INTEGER,created_at TEXT NOT NULL)');
    await d.execute('CREATE TABLE user_profile(id INTEGER PRIMARY KEY CHECK(id=1),name TEXT,age INTEGER,sex TEXT,height REAL,weight REAL,experience TEXT,specialization TEXT,goals TEXT)');
  }

  Future<void> createDemoCycleIfNeeded() async {
    final n = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM cycles')) ?? 0;
    if (n > 0) return;
    final c = await db.insert('cycles', {
      'name': 'Первый силовой цикл',
      'weeks': 4,
      'created_at': DateTime.now().toIso8601String(),
    });
    final squat = await db.insert('exercises', {'name': 'Присед со штангой', 'category': 'Ноги'});
    final bench = await db.insert('exercises', {'name': 'Жим лёжа', 'category': 'Грудь'});
    final dead = await db.insert('exercises', {'name': 'Становая тяга', 'category': 'Спина'});

    for (var w = 1; w <= 4; w++) {
      final wi = await db.insert('weeks', {'cycle_id': c, 'week_no': w});
      final day = await db.insert('days', {
        'week_id': wi,
        'day_no': 1,
        'name': 'Силовая тренировка',
      });
      final wo = await db.insert('workouts', {'day_id': day, 'cycle_id': c});
      for (final ex in [squat, bench, dead]) {
        final sort = [squat, bench, dead].indexOf(ex);
        final we = await db.insert('workout_exercises', {
          'workout_id': wo,
          'exercise_id': ex,
          'sort_no': sort,
        });
        for (var s = 1; s <= 4; s++) {
          final base = ex == dead ? 120 : ex == squat ? 100 : 80;
          await db.insert('planned_sets', {
            'workout_exercise_id': we,
            'set_no': s,
            'weight': base + (w - 1) * 2.5,
            'reps': 5,
          });
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> nextWorkouts() => db.rawQuery('''
    SELECT w.id,w.status,d.name,wk.week_no,d.day_no,c.name cycle_name
    FROM workouts w
    JOIN days d ON d.id=w.day_id
    JOIN weeks wk ON wk.id=d.week_id
    JOIN cycles c ON c.id=wk.cycle_id
    WHERE w.status IN ("planned","in_progress")
    ORDER BY wk.week_no,d.day_no LIMIT 30
  ''');

  Future<List<Map<String, dynamic>>> workoutSets(int workoutId) => db.rawQuery('''
    SELECT ps.id set_id,ps.set_no,ps.weight planned_weight,ps.reps planned_reps,ps.percentage planned_percentage,
    ps.rpe planned_rpe,ps.rir planned_rir,
    we.exercise_id,e.name exercise_name,a.weight actual_weight,a.reps actual_reps
    FROM planned_sets ps
    JOIN workout_exercises we ON we.id=ps.workout_exercise_id
    JOIN exercises e ON e.id=we.exercise_id
    LEFT JOIN actual_sets a ON a.planned_set_id=ps.id
    WHERE we.workout_id=? ORDER BY we.sort_no,ps.set_no
  ''', [workoutId]);

  Future<void> startWorkout(int id) async {
    await db.update(
      'workouts',
      {'status': 'in_progress', 'started_at': DateTime.now().toIso8601String()},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> saveActualSet(int id, double weight, int reps) async {
    await db.delete('actual_sets', where: 'planned_set_id=?', whereArgs: [id]);
    await db.insert('actual_sets', {
      'planned_set_id': id,
      'weight': weight,
      'reps': reps,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<double> planCompletion(int workoutId) async {
    final r = await db.rawQuery('''
      SELECT COUNT(ps.id) total, COUNT(a.id) done
      FROM planned_sets ps
      JOIN workout_exercises we ON we.id=ps.workout_exercise_id
      LEFT JOIN actual_sets a ON a.planned_set_id=ps.id
      WHERE we.workout_id=?
    ''', [workoutId]);
    final total = (r.first['total'] as num?) ?? 0;
    final done = (r.first['done'] as num?) ?? 0;
    return total == 0 ? 0 : done / total;
  }

  Future<Map<String, num>> workoutStats(int workoutId) async {
    final r = await db.rawQuery('''
      SELECT COALESCE(SUM(a.weight*a.reps),0) tonnage,
             COALESCE(SUM(a.reps),0) reps,
             COUNT(a.id) sets
      FROM actual_sets a
      JOIN planned_sets p ON p.id=a.planned_set_id
      JOIN workout_exercises x ON x.id=p.workout_exercise_id
      WHERE x.workout_id=?
    ''', [workoutId]);
    final x = r.first;
    return {
      'tonnage': (x['tonnage'] as num?) ?? 0,
      'reps': (x['reps'] as num?) ?? 0,
      'sets': (x['sets'] as num?) ?? 0,
    };
  }

  Future<void> finishWorkout(int id, int seconds) async {
    await db.update(
      'workouts',
      {
        'status': 'done',
        'finished_at': DateTime.now().toIso8601String(),
        'duration_sec': seconds,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> history() => db.rawQuery('''
    SELECT w.id,d.name,w.finished_at,w.duration_sec,w.status,wk.week_no,c.name cycle_name,
    COALESCE(
      (SELECT SUM(a.weight*a.reps)
       FROM actual_sets a
       JOIN planned_sets p ON p.id=a.planned_set_id
       JOIN workout_exercises x ON x.id=p.workout_exercise_id
       WHERE x.workout_id=w.id),0) tonnage
    FROM workouts w
    JOIN days d ON d.id=w.day_id
    JOIN weeks wk ON wk.id=d.week_id
    JOIN cycles c ON c.id=wk.cycle_id
    WHERE w.status="done"
    ORDER BY w.finished_at DESC
  ''');

  Future<Map<String, num>> totals() async {
    final r = await db.rawQuery('''
      SELECT COUNT(DISTINCT w.id) workouts,
             COALESCE(SUM(a.weight*a.reps),0) tonnage,
             COALESCE(SUM(a.reps),0) reps,
             COUNT(a.id) sets
      FROM actual_sets a
      JOIN planned_sets ps ON ps.id=a.planned_set_id
      JOIN workout_exercises we ON we.id=ps.workout_exercise_id
      JOIN workouts w ON w.id=we.workout_id
    ''');
    final x = r.first;
    return {
      'workouts': (x['workouts'] as num?) ?? 0,
      'tonnage': (x['tonnage'] as num?) ?? 0,
      'reps': (x['reps'] as num?) ?? 0,
      'sets': (x['sets'] as num?) ?? 0,
    };
  }

  Future<Map<String, dynamic>?> profile() async {
    final rows = await db.query('user_profile', where: 'id=1', limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> saveProfile(Map<String, dynamic> data) => db.insert(
        'user_profile',
        {'id': 1, ...data},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
  Future<List<Map<String, dynamic>>> allCycles() => db.query('cycles', orderBy: 'created_at DESC');

  Future<Map<String, dynamic>?> getCycle(int id) async {
    final rows = await db.query('cycles', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, dynamic>>> weeksForCycle(int cycleId) =>
      db.query('weeks', where: 'cycle_id=?', whereArgs: [cycleId], orderBy: 'week_no');

  Future<List<Map<String, dynamic>>> daysForWeek(int weekId) =>
      db.query('days', where: 'week_id=?', whereArgs: [weekId], orderBy: 'day_no');

  Future<List<Map<String, dynamic>>> exercisesForWorkout(int workoutId) => db.rawQuery('''
    SELECT we.id workout_exercise_id, we.sort_no, e.id exercise_id, e.name exercise_name
    FROM workout_exercises we
    JOIN exercises e ON e.id=we.exercise_id
    WHERE we.workout_id=? ORDER BY we.sort_no
  ''', [workoutId]);

  Future<List<Map<String, dynamic>>> setsForWorkoutExercise(int workoutExerciseId) =>
      db.query('planned_sets', where: 'workout_exercise_id=?', whereArgs: [workoutExerciseId], orderBy: 'set_no');

  Future<int> createCycle(String name, {int weeks = 1}) async {
    final id = await db.insert('cycles', {
      'name': name.trim().isEmpty ? 'Новый тренировочный цикл' : name.trim(),
      'weeks': max(1, weeks),
      'created_at': DateTime.now().toIso8601String(),
    });
    for (var i = 1; i <= max(1, weeks); i++) {
      final weekId = await db.insert('weeks', {'cycle_id': id, 'week_no': i});
      final dayId = await db.insert('days', {'week_id': weekId, 'day_no': 1, 'name': 'Тренировка 1'});
      await db.insert('workouts', {'day_id': dayId, 'cycle_id': id});
    }
    return id;
  }

  Future<void> updateCycle(int id, String name, int weeks) async {
    await db.update('cycles', {'name': name.trim(), 'weeks': weeks}, where: 'id=?', whereArgs: [id]);
  }

  Future<int> addWeek(int cycleId) async {
    final rows = await weeksForCycle(cycleId);
    final next = rows.isEmpty ? 1 : (rows.last['week_no'] as int) + 1;
    final weekId = await db.insert('weeks', {'cycle_id': cycleId, 'week_no': next});
    final dayId = await db.insert('days', {'week_id': weekId, 'day_no': 1, 'name': 'Тренировка 1'});
    await db.insert('workouts', {'day_id': dayId, 'cycle_id': cycleId});
    await db.update('cycles', {'weeks': next}, where: 'id=?', whereArgs: [cycleId]);
    return weekId;
  }

  Future<void> updateDay(int id, String name) => db.update(
        'days', {'name': name.trim().isEmpty ? 'Тренировка' : name.trim()},
        where: 'id=?', whereArgs: [id]);

  Future<int> addDay(int weekId) async {
    final rows = await daysForWeek(weekId);
    final next = rows.length + 1;
    final week = await db.query('weeks', where: 'id=?', whereArgs: [weekId], limit: 1);
    final cycleId = week.isEmpty ? null : week.first['cycle_id'];
    final dayId = await db.insert('days', {'week_id': weekId, 'day_no': next, 'name': 'Тренировка ' + next.toString()});
    await db.insert('workouts', {'day_id': dayId, 'cycle_id': cycleId});
    return dayId;
  }

  Future<int> _workoutForDay(int dayId) async {
    final rows = await db.query('workouts', where: 'day_id=?', whereArgs: [dayId], limit: 1);
    if (rows.isNotEmpty) return rows.first['id'] as int;
    final day = await db.query('days', where: 'id=?', whereArgs: [dayId], limit: 1);
    if (day.isEmpty) throw StateError('День не найден');
    final week = await db.query('weeks', where: 'id=?', whereArgs: [day.first['week_id']], limit: 1);
    final cycleId = week.isEmpty ? null : week.first['cycle_id'];
    return db.insert('workouts', {'day_id': dayId, 'cycle_id': cycleId});
  }

  Future<int> addExerciseToDay(int dayId, String exerciseName) async {
    final workoutId = await _workoutForDay(dayId);
    final existing = await db.query('exercises', where: 'LOWER(name)=LOWER(?)', whereArgs: [exerciseName.trim()], limit: 1);
    final exerciseId = existing.isNotEmpty
        ? existing.first['id'] as int
        : await db.insert('exercises', {'name': exerciseName.trim(), 'category': 'Другое'});
    final current = await db.query('workout_exercises', where: 'workout_id=? AND exercise_id=?', whereArgs: [workoutId, exerciseId], limit: 1);
    if (current.isNotEmpty) return current.first['id'] as int;
    final count = Sqflite.firstIntValue(await db.rawQuery(
      'SELECT COUNT(*) FROM workout_exercises WHERE workout_id=?', [workoutId])) ?? 0;
    return db.insert('workout_exercises', {
      'workout_id': workoutId, 'exercise_id': exerciseId, 'sort_no': count,
    });
  }

  Future<void> renameExercise(int exerciseId, String name) =>
      db.update('exercises', {'name': name.trim()}, where: 'id=?', whereArgs: [exerciseId]);

  Future<void> addPlannedSet(int workoutExerciseId, {double? weight, int? reps, double? percentage, double? rpe, double? rir, String? scheme}) async {
    final rows = await setsForWorkoutExercise(workoutExerciseId);
    final next = rows.length + 1;
    await db.insert('planned_sets', {
      'workout_exercise_id': workoutExerciseId,
      'set_no': next,
      'weight': weight,
      'reps': reps ?? 5,
      'percentage': percentage,
      'rpe': rpe,
      'rir': rir,
      'scheme': scheme,
    });
  }

  Future<void> updatePlannedSet(int id, {double? weight, int? reps, double? percentage, double? rpe, double? rir, String? scheme}) =>
      db.update('planned_sets', {
        'weight': weight, 'reps': reps ?? 0, 'percentage': percentage, 'rpe': rpe, 'rir': rir, 'scheme': scheme,
      }, where: 'id=?', whereArgs: [id]);

  Future<void> deletePlannedSet(int id) => db.delete('planned_sets', where: 'id=?', whereArgs: [id]);

  Future<void> deleteWorkoutExercise(int id) async {
    await db.delete('planned_sets', where: 'workout_exercise_id=?', whereArgs: [id]);
    await db.delete('workout_exercises', where: 'id=?', whereArgs: [id]);
  }

  Future<int> saveImportedProgram(dynamic draft) async {
    final id = await createCycle(draft.name, weeks: draft.weeks.length);
    for (var wi = 0; wi < draft.weeks.length; wi++) {
      final sourceWeek = draft.weeks[wi];
      final weekRows = await weeksForCycle(id);
      int weekId = weekRows.isNotEmpty && wi < weekRows.length
          ? weekRows[wi]['id'] as int
          : await addWeek(id);
      for (var di = 0; di < sourceWeek.days.length; di++) {
        final sourceDay = sourceWeek.days[di];
        var dayRows = await daysForWeek(weekId);
        int dayId;
        if (di < dayRows.length) {
          dayId = dayRows[di]['id'] as int;
          await updateDay(dayId, sourceDay.name);
        } else {
          dayId = await addDay(weekId);
          await updateDay(dayId, sourceDay.name);
        }
        for (final sourceExercise in sourceDay.exercises) {
          final weId = await addExerciseToDay(dayId, sourceExercise.name);
          for (final sourceSet in sourceExercise.sets) {
            await addPlannedSet(weId, weight: sourceSet.weight, reps: sourceSet.reps, percentage: sourceSet.percentage, rpe: sourceSet.rpe, rir: sourceSet.rir, scheme: sourceSet.scheme);
            final all = await setsForWorkoutExercise(weId);
            if (all.isNotEmpty) {
              final last = all.last;
              await updatePlannedSet(last['id'] as int,
                weight: sourceSet.weight, reps: sourceSet.reps,
                percentage: sourceSet.percentage, rpe: sourceSet.rpe, rir: sourceSet.rir);
            }
          }
        }
      }
    }
    return id;
  }

}
