import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_app/api.dart';
import 'package:schedule_app/screens/changes_screen.dart';
import 'package:schedule_app/services/notif_service.dart';

ScheduleChange ch(String text, [String ts = '2026-11-05T15:06:49']) =>
    ScheduleChange(ts, text, 'ИС-24');

void main() {
  const edited = '✏️ Изменение в паре\n📅 12 ноября 2026, четверг\n🔢 5 пара\n'
      '⏰ Время: 12:40 - 13:30 12:40 - 13:30 → 10:40 - 11:10 10:40 - 11:10\n'
      '🚪 Кабинет: 301 → 105 Лаборатория';
  const added = '➕ Добавлена пара\n📅 14 ноября 2026, суббота\n'
      '🔢 8 пара | 12:40 - 13:10 12:40 - 13:10\n📚 Безопасная среда\n'
      '🚪 107 Уход\n👤 Зобал Елена Валентиновна';
  const removed = '➖ Удалена пара\n📅 07 ноября 2026, суббота\n'
      '🔢 4 пара | 10:00 - 10:30 10:00 - 10:30\n📚 Безопасная среда';

  test('изменение: день, пара, поля «было → стало»', () {
    final c = ch(edited);
    expect(c.kind, ChangeKind.edited);
    expect(c.day, DateTime(2026, 11, 12));
    expect(c.weekday, 'четверг');
    expect(c.pairNum, '5');
    expect(c.fields.length, 2);
    expect(c.fields[0].label, 'Время');
    expect(c.fields[0].before, '12:40 - 13:30 12:40 - 13:30');
    expect(c.fields[0].after, '10:40 - 11:10 10:40 - 11:10');
    expect(c.fields[1].label, 'Кабинет');
    expect(c.fields[1].before, '301');
    expect(c.fields[1].after, '105 Лаборатория');
  });

  test('добавленная пара: время из строки номера, поля без «было»', () {
    final c = ch(added);
    expect(c.kind, ChangeKind.added);
    expect(c.pairNum, '8');
    expect(c.pairTime, '12:40 - 13:10 12:40 - 13:10');
    expect(c.fields.map((f) => f.label), ['Предмет', 'Кабинет', 'Преподаватель']);
    expect(c.fields.every((f) => f.before.isEmpty), true);
    expect(c.fields.first.after, 'Безопасная среда');
  });

  test('удалённая пара и неизвестный текст', () {
    expect(ch(removed).kind, ChangeKind.removed);
    final odd = ch('Что-то новое от сервера');
    expect(odd.kind, ChangeKind.other);
    expect(odd.day, isNull);
    expect(odd.fields, isEmpty);
  });

  test('предмет с двоеточием внутри не режется как подпись', () {
    final c = ch('✏️ Изменение в паре\n📅 12 ноября 2026, четверг\n🔢 2 пара\n'
        '📚 Предмет: МДК 01.01: Основы → Физика');
    expect(c.fields.single.label, 'Предмет');
    expect(c.fields.single.before, 'МДК 01.01: Основы');
    expect(c.fields.single.after, 'Физика');
  });

  test('группировка по дням и день по умолчанию', () {
    final days = ChangeDay.group([ch(added), ch(edited), ch(removed), ch('???')]);
    expect(days.map((d) => d.date),
        [DateTime(2026, 11, 7), DateTime(2026, 11, 12), DateTime(2026, 11, 14), null]);
    expect(ChangeDay.defaultIndex(days, DateTime(2026, 11, 11, 9)), 1);
    expect(ChangeDay.defaultIndex(days, DateTime(2026, 11, 12, 23)), 1);
    expect(ChangeDay.defaultIndex(days, DateTime(2026, 12, 1)), 2);
  });

  test('правки одной пары сводятся к итогу, «туда-обратно» пропадает', () {
    String e(String a, String b, [String extra = '']) =>
        '✏️ Изменение в паре\n📅 12 ноября 2026, четверг\n🔢 2 пара\n🚪 Кабинет: $a → $b$extra';
    // 301 → 105 → 301: ничего не изменилось
    expect(ChangeDay.group([ch(e('105', '301'), '2'), ch(e('301', '105'), '1')]), isEmpty);
    // 301 → 105 → 207 и по пути поменяли время
    final net = ChangeDay.group([
      ch(e('105', '207'), '2'),
      ch(e('301', '105', '\n⏰ Время: 08:00 - 09:40 → 10:00 - 11:40'), '1'),
    ]).single.items.single;
    expect(net.fields.map((f) => '${f.label}:${f.before}>${f.after}'),
        ['Кабинет:301>207', 'Время:08:00 - 09:40>10:00 - 11:40']);
    expect(net.pairNum, '2');
    expect(net.day, DateTime(2026, 11, 12));
    // правили, потом сняли — показываем снятие
    final del = ChangeDay.group([
      ch('➖ Удалена пара\n📅 12 ноября 2026, четверг\n🔢 2 пара | 08:00 - 09:40\n📚 Физика', '2'),
      ch(e('301', '105'), '1'),
    ]).single.items.single;
    expect(del.kind, ChangeKind.removed);
  });

  test('лента преподавателя: группа в строке пары, «Снята пара»', () {
    final c = ch('✏️ Изменение в паре\n📅 07 ноября 2026, суббота\n🔢 3 пара, 👥 ЗЧС-26\n'
        '⏰ Время: 10:20 - 11:10 → 09:20 - 09:50');
    expect(c.pairNum, '3');
    expect(c.pairGroup, 'ЗЧС-26');
    expect(c.fields.first.label, 'Группа');
    expect(c.fields.first.after, 'ЗЧС-26');
    final d = ch('➖ Снята пара\n📅 07 ноября 2026, суббота\n🔢 2 пара | 09:10 - 10:00\n📚 Физика\n👥 РН-26П\n🚪 204');
    expect(d.kind, ChangeKind.removed);
    expect(d.fields.map((f) => f.label), ['Предмет', 'Группа', 'Кабинет']);
    // разные группы на одной паре не склеиваются
    final two = ChangeDay.group([
      ch('✏️ Изменение в паре\n📅 07 ноября 2026, суббота\n🔢 3 пара, 👥 А-1\n🚪 Кабинет: 1 → 2', '1'),
      ch('✏️ Изменение в паре\n📅 07 ноября 2026, суббота\n🔢 3 пара, 👥 Б-2\n🚪 Кабинет: 2 → 1', '2'),
    ]).single.items;
    expect(two.length, 2);
  });

  test('текст уведомления: только предстоящие дни, по порядку, без повторов', () {
    final list = [ch(added), ch(edited), ch(edited), ch(removed)];
    expect(NotifService.daysSummary(list, DateTime(2026, 11, 11, 10)),
        'четверг 12.11, суббота 14.11');
    expect(NotifService.daysSummary(list, DateTime(2026, 11, 20)), '');
  });

  test('подгруппы: чужие пары убираются, общие остаются', () {
    final data = ScheduleData.fromJson({
      'group_name': 'ИС-24',
      'days': [
        {
          'title': '12 ноября 2026, четверг',
          'date': '2026-11-12',
          'lessons': [
            {'num': '1', 'time': '08:00 - 09:40', 'subgroups': [{'subject': 'Физика'}]},
            {'num': '2', 'time': '09:50 - 11:40', 'subgroups': [{'subject': 'ИТ  (1 гр.)'}]},
            {'num': '4', 'time': '13:00 - 14:40', 'subgroups': [{'subject': 'ИТ  (2 гр.)'}]},
            {'num': '5', 'time': '14:50 - 16:20', 'subgroups': [
              {'subject': 'Англ (1 гр.)', 'room': '1'},
              {'subject': 'Англ (2 гр.)', 'room': '2'},
            ]},
          ],
        }
      ],
    });
    List<String> nums(ScheduleData d) => d.days.first.lessons
        .where((l) => l.subgroups.isNotEmpty)
        .map((l) => l.num)
        .toList();
    expect(nums(data.forSubgroup(0)), ['1', '2', '4', '5']);
    expect(nums(data.forSubgroup(1)), ['1', '2', '5']);
    expect(nums(data.forSubgroup(2)), ['1', '4', '5']);
    expect(data.forSubgroup(2).days.first.lessons.last.subgroups.single.room, '2');
  });

  test('оценки в ячейке журнала', () {
    expect(JournalData.gradesIn('5'), [5]);
    expect(JournalData.gradesIn('5/4'), [5, 4]);
    expect(JournalData.gradesIn('4 5'), [4, 5]);
    expect(JournalData.gradesIn('зач'), isEmpty);
    expect(JournalData.gradesIn(''), isEmpty);
    expect(JournalData.gradesIn('н/а'), isEmpty);
  });
}
