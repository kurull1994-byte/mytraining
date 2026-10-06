import 'package:flutter_test/flutter_test.dart';
import 'package:my_workout_diary/core/app.dart';

void main() {
  testWidgets('app starts', (tester) async {
    await tester.pumpWidget(const MyWorkoutDiaryApp());
    expect(find.text('МОЙ ДНЕВНИК'), findsOneWidget);
  });
}
