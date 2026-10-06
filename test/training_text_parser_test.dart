import 'package:flutter_test/flutter_test.dart';
import '../lib/services/training_text_parser.dart';

void main() {
  test('parses week, day, scheme, percentage, RPE and RIR', () {
    final draft=TrainingTextParser.parse('''
Неделя 2
Тренировка 1
Присед со штангой 5x5 100 кг @75%
Жим лёжа 4x8 80 кг RPE 8
Тяга 3xAMRAP 120 кг RIR 2
''');
    expect(draft.weeks.length,1);
    expect(draft.weeks.first.number,2);
    expect(draft.weeks.first.days.length,1);
    final exercises=draft.weeks.first.days.first.exercises;
    expect(exercises.length,3);
    expect(exercises[0].sets.length,5);
    expect(exercises[0].sets.first.weight,100);
    expect(exercises[0].sets.first.percentage,75);
    expect(exercises[1].sets.length,4);
    expect(exercises[1].sets.first.rpe,8);
    expect(exercises[2].sets.length,3);
    expect(exercises[2].sets.first.reps,null);
    expect(exercises[2].sets.first.rir,2);
  });

  test('converts AI json without inventing values', () {
    final draft=TrainingTextParser.fromAiJson({
      'name':'Силовой цикл',
      'weeks':[{
        'number':1,
        'days':[{
          'name':'День A',
          'exercises':[{
            'name':'Присед',
            'sets':[{
              'weight':null,
              'reps':5,
              'percentage':80,
              'rpe':null,
              'rir':null,
              'scheme':'5x5'
            }]
          }]
        }]
      }],
      'warnings':['Вес не указан'],
      'missing_data':['Присед: вес']
    });
    final set=draft.weeks.first.days.first.exercises.first.sets.first;
    expect(set.weight,isNull);
    expect(set.percentage,80);
    expect(set.reps,5);
    expect(draft.warnings,contains('Вес не указан'));
  });
  test('parses eight-week exercise matrix into separate weeks and sets', () {
    final draft=TrainingTextParser.parse('''
8-недельный цикл

ПОНЕДЕЛЬНИК (Грудь, Плечи, Трицепс)
Упражнение Нед1 Нед2 Нед3 Нед4 Нед5 Нед6 Нед7 Нед8
Жим штанги лёжа 60×10, 3 80×8, 4 90×8, 4 100×8, 4 102,5×8, 4 105×8, 4 107,5×8, 4 60×10, 3
Жим гантелей на наклонной 20×10, 3 30×10, 3 34×10, 3 37,5×10, 3 38,5×10, 3 40×10, 3 40×10, 3 20×10, 3
Разводка гантелей лёжа 10×12, 3 13×12, 3 15×12, 3 17×12, 3 18×12, 3 18×12, 3 19×12, 3 10×12, 3

СРЕДА (Спина, Бицепс, Задняя дельта)
Упражнение Нед1 Нед2 Нед3 Нед4 Нед5 Нед6 Нед7 Нед8
Подтягивания быстрые 2×8 4×10 4×12 4×12 4×12 4×12 4×12 2×8
Подтягивания с ногами 90° 2×5 4×6 4×7 4×7 4×8 4×8 4×8 2×5
Медленные опускания с турника 2×3 3×3 3×3 3×3 3×3 3×3 2×3
Тяга штанги в наклоне 35×10, 3 55×10, 4 65×10, 4 70×10, 4 72,5×10, 4 75×10, 4 77,5×10, 4 35×10, 3

ПЯТНИЦА (Ноги, Плечи, Пресс)
Упражнение Нед1 Нед2 Нед3 Нед4 Нед5 Нед6 Нед7 Нед8
Приседания со штангой 60×8, 3 80×6, 4 90×6, 4 100×6, 4 105×6, 4 110×6, 4 110×6, 4 60×8, 3
Румынская тяга 70×10, 3 95×10, 4 110×10, 4 120×10, 4 125×10, 4 130×10, 4 130×10, 4 70×10, 3
Жим ногами 80×15, 3 120×15, 3 135×15, 3 150×15, 3 155×15, 3 160×15, 3 160×15, 3 80×15, 3
''');
    expect(draft.weeks.length,8);
    expect(draft.weeks[0].days.length,3);
    expect(draft.weeks[0].days.first.exercises.first.name,'Жим штанги лёжа');
    expect(draft.weeks[0].days.first.exercises.first.sets.length,3);
    expect(draft.weeks[0].days.first.exercises.first.sets.first.weight,60);
    expect(draft.weeks[0].days.first.exercises.first.sets.first.reps,10);
    expect(draft.weeks[4].days.first.exercises.first.sets.first.weight,102.5);
    expect(draft.weeks[4].days.first.exercises.first.sets.length,4);
    expect(draft.weeks[0].days[1].exercises.first.sets.first.weight,isNull);
    expect(draft.weeks[0].days[1].exercises.first.sets.length,2);
    expect(draft.weeks[0].days[2].exercises.first.sets.length,3);
  });

}
