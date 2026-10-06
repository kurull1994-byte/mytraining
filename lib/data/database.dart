import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

final databaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError(),
);

class AppDatabase {
  late Database db;

  Future<void> init() async {
    db = await openDatabase(
      join(await getDatabasesPath(), 'my_workout_diary.db'),
      version: 1,
      onCreate: (d, _) => _createSchema(d),
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
    await d.execute('CREATE TABLE planned_sets(id INTEGER PRIMARY KEY AUTOINCREMENT,workout_exercise_id INTEGER,set_no INTEGER,weight REAL,reps INTEGER,rpe REAL,rir REAL)');
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
    SELECT ps.id set_id,ps.set_no,ps.weight planned_weight,ps.reps planned_reps,
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
}
