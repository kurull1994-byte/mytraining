import 'package:flutter_test/flutter_test.dart';
import 'package:my_workout_diary/core/app.dart';

void main() {
  test('app widget can be constructed', () {
    expect(const MyWorkoutDiaryApp(), isA<MyWorkoutDiaryApp>());
  });
}
