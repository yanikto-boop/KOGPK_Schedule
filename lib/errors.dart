import 'api.dart';

/// Человеческий текст ошибки для экранов.
///
/// Сырой текст исключения показывать нельзя: в нём светятся адрес сервера
/// и внутренние детали (SocketException, ClientException и т.п.), которые
/// пользователю ничего не говорят.
String friendlyError(Object e) {
  final s = e.toString().toLowerCase();

  if (s.contains('bad ticket')) return 'Неверный номер зачётки';

  if (s.contains('journal unavailable')) {
    return 'Сайт колледжа сейчас не отвечает — журнал там периодически недоступен.\n'
        'Если зачётка верная, попробуйте ещё раз чуть позже.';
  }

  // Нет сети на устройстве или сервер недоступен.
  const offline = [
    'socketexception',
    'clientexception',
    'failed host lookup',
    'connection',
    'network is unreachable',
    'handshake',
    'timeout',
    'timeoutexception',
    'closed',
    'broken pipe',
  ];
  if (offline.any(s.contains)) {
    return 'Нет связи с сервером.\nПроверьте интернет и попробуйте ещё раз.';
  }

  // Сервер ответил, но с ошибкой.
  if (s.contains('50') && s.contains('ошибка')) {
    return 'Сервер сейчас недоступен.\nПопробуйте ещё раз через несколько минут.';
  }

  // Текст от нашего API ('detail') писался для людей — его можно показать.
  if (e is ApiException) return e.message;

  return 'Не удалось загрузить данные.\nПопробуйте ещё раз позже.';
}
