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
}
