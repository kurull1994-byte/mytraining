import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/database.dart';

class MyWorkoutDiaryApp extends StatelessWidget {
  const MyWorkoutDiaryApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Мой дневник тренировок',
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.orange,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF0D0F12),
      cardTheme: const CardTheme(color: Color(0xFF181B21)),
    ),
    home: const Shell(),
  );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final db = ref.read(databaseProvider);
    final pages = [
      HomePage(db: db, onStart: () => _startNext(db)),
      ProgramPage(db: db, onStart: (id) => _openWorkout(db, id)),
      StatisticsPage(db: db),
      HistoryPage(db: db),
      ProfilePage(db: db),
    ];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index < 2 ? FloatingActionButton.extended(
        onPressed: () => _startNext(db),
        icon: const Icon(Icons.play_arrow), label: const Text('Тренировка'),
      ) : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Программа'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), label: 'Статистика'),
          NavigationDestination(icon: Icon(Icons.history), label: 'История'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Профиль'),
        ],
      ),
    );
  }

  Future<void> _startNext(AppDatabase db) async {
    final rows = await db.nextWorkouts();
    if (!mounted) return;
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Нет запланированных тренировок')));
      return;
    }
    await _openWorkout(db, rows.first['id'] as int);
  }

  Future<void> _openWorkout(AppDatabase db, int id) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveWorkoutPage(db: db, workoutId: id)));
    if (mounted) setState(() {});
  }
}

class HomePage extends StatelessWidget {
  final AppDatabase db; final VoidCallback onStart;
  const HomePage({super.key, required this.db, required this.onStart});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: db.nextWorkouts(),
    builder: (context, snap) {
      final rows = snap.data ?? const <Map<String, dynamic>>[];
      final next = rows.isEmpty ? null : rows.first;
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 52, 16, 120),
        children: [
          Text('МОЙ ДНЕВНИК', style: Theme.of(context).textTheme.labelLarge?.copyWith(letterSpacing: 2, color: Colors.orange)),
          const SizedBox(height: 4),
          Text('Тренируйся. Записывай. Прогрессируй.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          Card(child: Padding(
            padding: const EdgeInsets.all(18),
            child: next == null ? const Text('Все запланированные тренировки выполнены.') : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('БЛИЖАЙШАЯ ТРЕНИРОВКА'),
                const SizedBox(height: 10),
                Text('Неделя ${next['week_no']} • ${next['name']}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                Text('${next['cycle_name']}'),
                const SizedBox(height: 16),
                FilledButton.icon(onPressed: onStart, icon: const Icon(Icons.play_arrow), label: const Text('Начать')),
              ],
            ),
          )),
          const SizedBox(height: 14),
          FutureBuilder<Map<String, num>>(
            future: db.totals(),
            builder: (context, s) {
              final x = s.data;
              return Row(children: [
                _metric('Тренировки', '${x?['workouts']?.toInt() ?? 0}'),
                _metric('Тоннаж', '${(x?['tonnage'] ?? 0).toStringAsFixed(0)} кг'),
                _metric('Подходы', '${x?['sets']?.toInt() ?? 0}')
              ].map((w) => Expanded(child: w)).toList());
            },
          ),
        ],
      );
    },
  );
}

Widget _metric(String title, String value) => Card(
  margin: const EdgeInsets.all(4),
  child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(children: [
      Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4), Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
    ]),
  ),
);

class ProgramPage extends StatelessWidget {
  final AppDatabase db; final Future<void> Function(int) onStart;
  const ProgramPage({super.key, required this.db, required this.onStart});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: db.nextWorkouts(),
    builder: (context, snap) {
      final rows = snap.data ?? const <Map<String, dynamic>>[];
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 52, 16, 120),
        children: [
          Text('ПРОГРАММА', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          if (rows.isEmpty) const Card(child: ListTile(title: Text('Цикл завершён'))),
          ...rows.map((r) => Card(child: ListTile(
            title: Text('Неделя ${r['week_no']} • ${r['name']}'),
            subtitle: Text('${r['cycle_name']} · ${r['status']}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => onStart(r['id'] as int),
          ))),
        ],
      );
    },
  );
}

class ActiveWorkoutPage extends StatefulWidget {
  final AppDatabase db; final int workoutId;
  const ActiveWorkoutPage({super.key, required this.db, required this.workoutId});
  @override State<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends State<ActiveWorkoutPage> {
  Timer? timer; Timer? restTimer; int elapsed = 0; int rest = 120; bool restRunning = false;
  @override void dispose() { timer?.cancel(); restTimer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: _load(),
    builder: (context, snap) {
      final sets = snap.data ?? const <Map<String, dynamic>>[];
      return Scaffold(
        appBar: AppBar(title: const Text('Тренировка')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Row(children: [
              Text(_fmt(elapsed), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _toggleWorkoutTimer,
                icon: Icon(timer == null ? Icons.play_arrow : Icons.pause),
                label: Text(timer == null ? 'Старт' : 'Пауза'),
              ),
            ]),
            const SizedBox(height: 8),
            _restCard(),
            const SizedBox(height: 10),
            ..._groupSets(sets),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                timer?.cancel();
                await widget.db.finishWorkout(widget.workoutId, elapsed);
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Завершить тренировку'),
            ),
          ],
        ),
      );
    },
  );

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await widget.db.nextWorkouts();
    final current = rows.where((x) => x['id'] == widget.workoutId);
    if (current.isNotEmpty && current.first['status'] == 'planned') {
      await widget.db.startWorkout(widget.workoutId);
      _toggleWorkoutTimer();
    }
    return widget.db.workoutSets(widget.workoutId);
  }

  List<Widget> _groupSets(List<Map<String, dynamic>> sets) {
    final out = <Widget>[]; String? last;
    for (final s in sets) {
      final ex = '${s['exercise_name']}';
      if (ex != last) {
        out.add(Padding(padding: const EdgeInsets.only(top: 10, bottom: 6), child: Text(ex, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))));
        last = ex;
      }
      out.add(_SetRow(db: widget.db, row: s, onSaved: () => setState(() {}), onRest: _startRest));
    }
    return out;
  }

  Widget _restCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        const Icon(Icons.timer_outlined), const SizedBox(width: 10),
        Text(_fmt(rest), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(onPressed: restRunning ? null : _startRest, icon: const Icon(Icons.play_arrow)),
        IconButton(onPressed: _pauseRest, icon: const Icon(Icons.pause)),
        IconButton(onPressed: () => setState(() => rest = 120), icon: const Icon(Icons.refresh)),
        IconButton(onPressed: () => setState(() => rest += 30), icon: const Icon(Icons.add_circle_outline)),
        IconButton(onPressed: () => setState(() => rest = rest > 30 ? rest - 30 : 0), icon: const Icon(Icons.remove_circle_outline)),
      ]),
    ),
  );

  void _toggleWorkoutTimer() {
    if (timer != null) { timer!.cancel(); timer = null; setState(() {}); return; }
    timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => elapsed++));
    setState(() {});
  }

  void _startRest() {
    if (restRunning || rest <= 0) return;
    restRunning = true;
    restTimer?.cancel();
    restTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (rest <= 1) { _pauseRest(); setState(() => rest = 0); } else { setState(() => rest--); }
    });
    setState(() {});
  }

  void _pauseRest() { restTimer?.cancel(); restTimer = null; restRunning = false; setState(() {}); }
}

class _SetRow extends StatefulWidget {
  final AppDatabase db; final Map<String, dynamic> row; final VoidCallback onSaved; final VoidCallback onRest;
  const _SetRow({required this.db, required this.row, required this.onSaved, required this.onRest});
  @override State<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends State<_SetRow> {
  late final TextEditingController weight; late final TextEditingController reps;
  @override void initState() { super.initState(); weight = TextEditingController(text: '${widget.row['actual_weight'] ?? widget.row['planned_weight']}'); reps = TextEditingController(text: '${widget.row['actual_reps'] ?? widget.row['planned_reps']}'); }
  @override void dispose() { weight.dispose(); reps.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Row(children: [
        SizedBox(width: 38, child: Text('#${widget.row['set_no']}')),
        Expanded(child: Text('План ${widget.row['planned_weight']} × ${widget.row['planned_reps']}')),
        SizedBox(width: 68, child: TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'кг'))),
        const SizedBox(width: 6),
        SizedBox(width: 55, child: TextField(controller: reps, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'повт.'))),
        IconButton(
          onPressed: () async {
            final w = double.tryParse(weight.text.replaceAll(',', '.')) ?? 0;
            final r = int.tryParse(reps.text) ?? 0;
            await widget.db.saveActualSet(widget.row['set_id'] as int, w, r);
            widget.onSaved();
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Подход сохранён')));
          },
          icon: const Icon(Icons.check_circle_outline),
        ),
        IconButton(onPressed: widget.onRest, icon: const Icon(Icons.timer_outlined)),
      ]),
    ),
  );
}

class StatisticsPage extends StatelessWidget {
  final AppDatabase db;
  const StatisticsPage({super.key, required this.db});
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, num>>(
    future: db.totals(),
    builder: (context, snap) {
      final x = snap.data;
      return ListView(padding: const EdgeInsets.fromLTRB(16, 52, 16, 120), children: [
        Text('СТАТИСТИКА', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        _bigStat('Тренировки', '${x?['workouts']?.toInt() ?? 0}'),
        _bigStat('Общий тоннаж', '${(x?['tonnage'] ?? 0).toStringAsFixed(1)} кг'),
        _bigStat('Повторения', '${x?['reps']?.toInt() ?? 0}'),
        _bigStat('Подходы', '${x?['sets']?.toInt() ?? 0}'),
        const Card(child: ListTile(leading: Icon(Icons.calculate_outlined), title: Text('Расчётный 1ПМ'), subtitle: Text('Будет подключён в следующем модуле статистики.'))),
      ]);
    },
  );
}

Widget _bigStat(String t, String v) => Card(child: ListTile(title: Text(t), trailing: Text(v, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold))));

class HistoryPage extends StatelessWidget {
  final AppDatabase db;
  const HistoryPage({super.key, required this.db});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Map<String, dynamic>>>(
    future: db.history(),
    builder: (context, snap) {
      final rows = snap.data ?? const <Map<String, dynamic>>[];
      return ListView(padding: const EdgeInsets.fromLTRB(16, 52, 16, 120), children: [
        Text('ИСТОРИЯ', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        if (rows.isEmpty) const Card(child: ListTile(title: Text('Пока нет завершённых тренировок'))),
        ...rows.map((r) => Card(child: ListTile(
          title: Text('${r['name']} · неделя ${r['week_no']}'),
          subtitle: Text('Тоннаж: ${(r['tonnage'] as num).toStringAsFixed(0)} кг'),
          trailing: const Icon(Icons.check_circle),
        ))),
      ]);
    },
  );
}

class ProfilePage extends StatefulWidget {
  final AppDatabase db;
  const ProfilePage({super.key, required this.db});
  @override State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final name = TextEditingController(), age = TextEditingController(), height = TextEditingController(), weight = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.db.profile().then((p) {
      if (p == null || !mounted) return;
      name.text = '${p['name'] ?? ''}'; age.text = '${p['age'] ?? ''}'; height.text = '${p['height'] ?? ''}'; weight.text = '${p['weight'] ?? ''}';
      setState(() {});
    });
  }
  @override void dispose() { name.dispose(); age.dispose(); height.dispose(); weight.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 52, 16, 120),
    children: [
      Text('ПРОФИЛЬ', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 16),
      TextField(controller: name, decoration: const InputDecoration(labelText: 'Имя / никнейм')),
      const SizedBox(height: 10),
      TextField(controller: age, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Возраст')),
      const SizedBox(height: 10),
      TextField(controller: height, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Рост, см')),
      const SizedBox(height: 10),
      TextField(controller: weight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Вес, кг')),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: () async {
          await widget.db.saveProfile({'name': name.text, 'age': int.tryParse(age.text), 'height': double.tryParse(height.text.replaceAll(',', '.')), 'weight': double.tryParse(weight.text.replaceAll(',', '.'))});
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Профиль сохранён')));
        },
        child: const Text('Сохранить'),
      ),
    ],
  );
}

String _fmt(int s) => '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
