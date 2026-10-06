import 'package:flutter/material.dart';
import '../data/database.dart';

class ProgramEditorPage extends StatefulWidget {
  final AppDatabase db; final int? cycleId;
  const ProgramEditorPage({super.key, required this.db, this.cycleId});
  @override State<ProgramEditorPage> createState() => _ProgramEditorPageState();
}
class _ProgramEditorPageState extends State<ProgramEditorPage> {
  int? id; final title=TextEditingController(); bool loading=true;
  @override void initState(){super.initState(); load();}
  @override void dispose(){title.dispose(); super.dispose();}
  Future<void> load() async {
    id=widget.cycleId ?? await widget.db.createCycle('Новый силовой цикл');
    final c=await widget.db.getCycle(id!); title.text=(c?['name']??'').toString();
    if(mounted)setState(()=>loading=false);
  }
  Future<void> save() async { final w=await widget.db.weeksForCycle(id!); await widget.db.updateCycle(id!,title.text,w.length); if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Сохранено'))); }
  Future<void> addWeek() async { await widget.db.addWeek(id!); if(mounted)setState((){}); }
  Future<void> addDay(int weekId) async { await widget.db.addDay(weekId); if(mounted)setState((){}); }
  Future<void> addExercise(int dayId) async {
    final c=TextEditingController();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Новое упражнение'),content:TextField(controller:c,autofocus:true),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim().isNotEmpty),child:const Text('Добавить'))]));
    if(ok==true){await widget.db.addExerciseToDay(dayId,c.text.trim());if(mounted)setState((){});} c.dispose();
  }
  Future<void> renameDay(int dayId,String current) async {
    final c=TextEditingController(text:current);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Тренировочный день'),content:TextField(controller:c,autofocus:true),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сохранить'))]));
    if(ok==true){await widget.db.updateDay(dayId,c.text);if(mounted)setState((){});} c.dispose();
  }
  Future<void> editSet(Map<String,dynamic> s) async {
    final w=TextEditingController(text:(s['weight']??'').toString()); final r=TextEditingController(text:(s['reps']??5).toString());
    final rpe=TextEditingController(text:(s['rpe']??'').toString()); final rir=TextEditingController(text:(s['rir']??'').toString());
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:Text('Подход '+s['set_no'].toString()),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:w,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Вес, кг')),TextField(controller:r,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Повторения')),TextField(controller:rpe,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'RPE')),TextField(controller:rir,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'RIR'))]),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сохранить'))]));
    if(ok==true){await widget.db.updatePlannedSet(s['id'] as int,weight:double.tryParse(w.text.replaceAll(',','.')),reps:int.tryParse(r.text),rpe:double.tryParse(rpe.text.replaceAll(',','.')),rir:double.tryParse(rir.text.replaceAll(',','.')));if(mounted)setState((){});} w.dispose();r.dispose();rpe.dispose();rir.dispose();
  }
  Future<void> renameExercise(int eid,String current) async {
    final c=TextEditingController(text:current);
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Изменить упражнение'),content:TextField(controller:c,autofocus:true),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Отмена')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Сохранить'))]));
    if(ok==true&&c.text.trim().isNotEmpty){await widget.db.renameExercise(eid,c.text);if(mounted)setState((){});} c.dispose();
  }
  Future<void> addSet(int weId) async {await widget.db.addPlannedSet(weId,reps:5);if(mounted)setState((){});}
  @override Widget build(BuildContext context){
    if(loading||id==null)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    return Scaffold(appBar:AppBar(title:const Text('Редактор программы'),actions:[IconButton(onPressed:save,icon:const Icon(Icons.save_outlined))]),body:ListView(padding:const EdgeInsets.fromLTRB(16,8,16,40),children:[
      TextField(controller:title,decoration:const InputDecoration(labelText:'Название цикла',prefixIcon:Icon(Icons.edit_outlined))),
      const SizedBox(height:12),
      FutureBuilder<List<Map<String,dynamic>>>(future:widget.db.weeksForCycle(id!),builder:(context,s){final weeks=s.data??const <Map<String,dynamic>>[];return Column(children:[...weeks.map((week)=>WeekEditor(db:widget.db,week:week,onChanged:()=>setState((){}),onAddDay:()=>addDay(week['id'] as int),onAddExercise:addExercise,onRenameDay:renameDay,onEditSet:editSet,onRenameExercise:renameExercise,onAddSet:addSet)),OutlinedButton.icon(onPressed:addWeek,icon:const Icon(Icons.add),label:const Text('Добавить неделю'))]);}),
    ]));
  }
}

class WeekEditor extends StatelessWidget {
  final AppDatabase db; final Map<String,dynamic> week; final VoidCallback onChanged,onAddDay; final Future<void> Function(int) onAddExercise,onAddSet; final Future<void> Function(int,String) onRenameDay,onRenameExercise; final Future<void> Function(Map<String,dynamic>) onEditSet;
  const WeekEditor({super.key,required this.db,required this.week,required this.onChanged,required this.onAddDay,required this.onAddExercise,required this.onRenameDay,required this.onEditSet,required this.onRenameExercise,required this.onAddSet});
  @override Widget build(BuildContext context)=>Card(child:ExpansionTile(initiallyExpanded:(week['week_no']==1),title:Text('Неделя '+week['week_no'].toString(),style:const TextStyle(fontWeight:FontWeight.w800)),children:[FutureBuilder<List<Map<String,dynamic>>>(future:db.daysForWeek(week['id'] as int),builder:(context,s){final days=s.data??const <Map<String,dynamic>>[];return Column(children:[...days.map((d)=>DayEditor(db:db,day:d,onChanged:onChanged,onAddExercise:onAddExercise,onRenameDay:onRenameDay,onEditSet:onEditSet,onRenameExercise:onRenameExercise,onAddSet:onAddSet)),TextButton.icon(onPressed:onAddDay,icon:const Icon(Icons.add),label:const Text('Добавить тренировочный день'))]);})]));
}

class DayEditor extends StatelessWidget {
  final AppDatabase db; final Map<String,dynamic> day; final VoidCallback onChanged; final Future<void> Function(int) onAddExercise,onAddSet; final Future<void> Function(int,String) onRenameDay,onRenameExercise; final Future<void> Function(Map<String,dynamic>) onEditSet;
  const DayEditor({super.key,required this.db,required this.day,required this.onChanged,required this.onAddExercise,required this.onRenameDay,required this.onEditSet,required this.onRenameExercise,required this.onAddSet});
  @override Widget build(BuildContext context)=>Card(color:const Color(0xFF111419),child:ExpansionTile(title:Text((day['name']??'Тренировка').toString()),children:[FutureBuilder<List<Map<String,dynamic>>>(future:db.db.query('workouts',where:'day_id=?',whereArgs:[day['id']],limit:1),builder:(context,s){if(!s.hasData||s.data!.isEmpty)return const SizedBox.shrink();final wid=s.data!.first['id'] as int;return FutureBuilder<List<Map<String,dynamic>>>(future:db.exercisesForWorkout(wid),builder:(context,e){final ex=e.data??const <Map<String,dynamic>>[];return Column(children:[...ex.map((x)=>ExerciseEditor(db:db,exercise:x,onChanged:onChanged,onEditSet:onEditSet,onRename:onRenameExercise,onAddSet:onAddSet)),Wrap(children:[TextButton.icon(onPressed:()=>onAddExercise(day['id'] as int),icon:const Icon(Icons.add),label:const Text('Добавить упражнение')),TextButton.icon(onPressed:()=>onRenameDay(day['id'] as int,(day['name']??'').toString()),icon:const Icon(Icons.edit_outlined),label:const Text('Переименовать'))])]);});})]));
}

class ExerciseEditor extends StatelessWidget {
  final AppDatabase db;
  final Map<String, dynamic> exercise;
  final VoidCallback onChanged;
  final Future<void> Function(Map<String, dynamic>) onEditSet;
  final Future<void> Function(int, String) onRename;
  final Future<void> Function(int) onAddSet;

  const ExerciseEditor({
    super.key,
    required this.db,
    required this.exercise,
    required this.onChanged,
    required this.onEditSet,
    required this.onRename,
    required this.onAddSet,
  });

  @override
  Widget build(BuildContext context) {
    final workoutExerciseId = exercise['workout_exercise_id'] as int;
    final exerciseId = exercise['exercise_id'] as int;
    final exerciseName = (exercise['exercise_name'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    exerciseName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => onRename(exerciseId, exerciseName),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: db.setsForWorkoutExercise(workoutExerciseId),
              builder: (context, snapshot) {
                final sets = snapshot.data ?? const <Map<String, dynamic>>[];
                return Column(
                  children: [
                    ...sets.map(
                      (set) => ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text(set['set_no'].toString()),
                        ),
                        title: Text(
                          (set['weight'] ?? '—').toString() +
                              ' кг × ' +
                              (set['reps'] ?? '—').toString(),
                        ),
                        subtitle: Text([
                          if (set['rpe'] != null) 'RPE ' + set['rpe'].toString(),
                          if (set['rir'] != null) 'RIR ' + set['rir'].toString(),
                        ].join(' · ')),
                        trailing: Wrap(
                          children: [
                            IconButton(
                              onPressed: () => onEditSet(set),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              onPressed: () async {
                                await db.deletePlannedSet(set['id'] as int);
                                onChanged();
                              },
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => onAddSet(workoutExerciseId),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить подход'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
