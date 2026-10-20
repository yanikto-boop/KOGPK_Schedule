import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/pair.dart';
import 'package:schedule_app/services/profile.dart';

void main() {
  test('короткое ФИО', () {
    expect(Profile.short('Иванов Иван Иванович'), 'Иванов И. И.');
    expect(Profile.short('Иванов'), 'Иванов');
  });

  test('режим хранится и сбрасывается в студента без потери группы', () async {
    SharedPreferences.setMockInitialValues({'group': '170П'});
    expect(await Profile.teacher(), isNull);
    var fired = 0;
    void l() => fired++;
    Profile.changed.addListener(l);
    await Profile.setTeacher('Иванов Иван Иванович');
    expect(await Profile.teacher(), 'Иванов Иван Иванович');
    await Profile.setTeacher(null);
    expect(await Profile.teacher(), isNull);
    final p = await SharedPreferences.getInstance();
    expect(p.getString('group'), '170П');
    expect(fired, 2);
    Profile.changed.removeListener(l);
  });

  test('пара преподавателя несёт группу', () {
    final data = ScheduleData.fromJson({
      'teacher': 'Иванов И. И.',
      'days': [
        {
          'title': '21 октября 2026, среда',
          'date': '2026-10-21',
          'lessons': [
            {'num': '2', 'time': '09:50 - 10:35 10:55 - 11:40',
             'subject': 'Математика', 'group': '170П', 'room': '204'}
          ]
        }
      ]
    }, teacherMode: true);
    final b = PairBlock.ofDay(data.days.first, DateTime(2026, 10, 21));
    expect(b.single.group, '170П');
    expect(b.single.teacher, '');
    expect(b.single.start, DateTime(2026, 10, 21, 9, 50));
  });
}
