import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case auto, ru, en
    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: return Lang.isRussian ? "Авто" : "Auto"
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

enum Lang {
    static var current: AppLanguage = .auto
    static var isRussian: Bool {
        switch current {
        case .ru: return true
        case .en: return false
        case .auto: return Locale.preferredLanguages.first?.hasPrefix("ru") == true
        }
    }
    static var code: String { isRussian ? "ru" : "en" }
}

func tr(_ s: String) -> String { Lang.isRussian ? (ruTable[s] ?? s) : s }
func trf(_ s: String, _ args: CVarArg...) -> String { String(format: tr(s), arguments: args) }

private let ruTable: [String: String] = [
    // header / general
    "Bluetooth MAC (AA:BB:CC:DD:EE:FF)": "Bluetooth MAC (AA:BB:CC:DD:EE:FF)",
    "Refresh paired devices": "Обновить список устройств",
    "Reconnect": "Переподключить", "Connect": "Подключить",
    "Battery": "Батарея",
    "Liquid Glass": "Жидкое стекло", "Connect popup": "Окно подключения", "Desktop widget": "Виджет на столе",
    "Start at login": "Запуск при входе", "Packet log": "Лог пакетов",
    "Language": "Язык",
    "Worn": "В ушах", "Not worn": "Не в ушах",
    "Left": "Левый", "Right": "Правый", "Case": "Кейс",
    // noise control
    "Noise control": "Шумоподавление", "Noise Cancellation": "Шумоподавление", "ANC": "ANC",
    "Adaptive": "Адаптивный", "Transparency": "Прозрачность", "Transp.": "Прозр.", "Off": "Выкл",
    "High": "Высокий", "Moderate": "Средний", "Mid": "Средний", "Low": "Низкий", "Auto": "Авто",
    "Put the earbuds in your ears to change noise control": "Наденьте наушники, чтобы менять шумоподавление",
    "Noise control off": "Шумоподавление выкл",
    "Earbuds in ear": "Наушники в ушах", "Earbuds removed": "Наушники сняты",
    // EQ
    "Sound Master EQ": "Sound Master EQ", "BassWave™": "BassWave™", "Enabled": "Включено",
    "Custom EQ": "Свой эквалайзер", "Name": "Название", "Create": "Создать", "Select": "Выбрать", "Delete": "Удалить",
    "Balanced": "Сбалансированный", "Clear Vocals": "Чистый вокал", "Bass": "Бас", "Bold": "Яркий",
    "Serenade": "Серенада", "DynAudio": "DynAudio",
    // gestures
    "Earbud controls": "Управление наушниками", "During a call": "Во время звонка",
    "Single-tap": "Одно касание", "Double-tap": "Двойное касание", "Triple-tap": "Тройное касание",
    "Slide": "Свайп", "Touch & hold": "Касание и удержание",
    "Play / Pause": "Пуск / Пауза", "None": "Нет", "Next track": "Следующий трек",
    "Previous track": "Предыдущий трек", "Voice Assistant": "Голосовой помощник",
    "Volume control": "Громкость", "Answer / End call": "Ответить / завершить", "Decline call": "Отклонить звонок",
    // status
    "Select a device and press Connect": "Выберите устройство и нажмите «Подключить»",
    "No paired OnePlus Buds found — pair in System Settings → Bluetooth or type a MAC":
        "Наушники OnePlus Buds не найдены — подключите их в Системных настройках → Bluetooth или введите MAC",
    "Type a MAC, then Connect": "Введите MAC и нажмите «Подключить»",
    "Waiting for earbuds to connect to macOS…": "Ждём подключения наушников к macOS…",
    "Pick a device or type a MAC first": "Сначала выберите устройство или введите MAC",
    "Invalid MAC address": "Неверный MAC-адрес",
    "Connecting to %@…": "Подключаемся к %@…",
    "Waiting for earbuds to connect… (error %d)": "Ждём подключения наушников… (ошибка %d)",
    "Waiting for earbuds to connect…": "Ждём подключения наушников…",
    "Connected to %@": "Подключено: %@",
    "Reconnecting…": "Переподключение…",
    "Send failed (error %d)": "Не удалось отправить (ошибка %d)",
    "Not connected": "Нет подключения", "Connected": "Подключено",
    "Login item failed: %@": "Автозапуск не удался: %@",
    "Slot is empty — create an EQ first": "Слот пуст — сначала создайте эквалайзер",
    "Slot is empty — nothing to delete": "Слот пуст — удалять нечего",
    // command labels
    "ANC on": "ANC включён", "ANC off": "ANC выключен",
    "ANC High": "ANC: высокий", "ANC Moderate": "ANC: средний", "ANC Low": "ANC: низкий", "ANC Auto": "ANC: авто",
    "EQ Balanced": "EQ: сбалансированный", "EQ Clear Vocals": "EQ: чистый вокал", "EQ Bass": "EQ: бас",
    "EQ Bold": "EQ: яркий", "EQ Serenade": "EQ: серенада", "EQ DynAudio": "EQ: DynAudio",
    "BassWave on (%@)": "BassWave включён (%@)", "BassWave off": "BassWave выключен", "BassWave %@": "BassWave %@",
    "Create EQ '%@'": "Создан EQ «%@»", "Select EQ '%@' (slot %d)": "Выбран EQ «%@» (слот %d)",
    "Delete EQ '%@' (slot %d)": "Удалён EQ «%@» (слот %d)",
    // notifications
    "%@ Connected": "%@ подключены", "%@ Disconnected": "%@ отключены",
    "Connected successfully": "Успешно подключено", "Last battery: %@": "Последний заряд: %@",
    "Bluetooth connection lost.": "Bluetooth-соединение потеряно.",
    // menu
    "Show": "Показать", "Quit": "Выйти",
    // popup settings
    "Connection popup": "Окно при подключении", "Theme": "Тема", "Preview": "Показать",
    "Show battery": "Показывать заряд", "Earbud action HUD": "Индикатор действий наушников (громкость, пауза)",
    "Playing": "Воспроизведение", "Paused": "Пауза", "Left earbud": "Левый наушник", "Right earbud": "Правый наушник", "Earbud": "Наушник", "Theme carousel": "Карусель тем", "Rotation": "Смена",
    "Every connection": "Каждое подключение", "Every day": "Каждый день", "Every week": "Каждую неделю",
    "Choose image or video…": "Выбрать картинку или видео…", "Blur": "Размытие",
    "Pick at least 2 themes for the carousel": "Выберите минимум 2 темы для карусели",
    "Glass": "Стекло", "Aurora": "Аврора", "Neon": "Неон", "Island": "Остров", "Minimal": "Минимал", "Custom": "Своя",
    // widget / log
    "Packets: %d": "Пакетов: %d", "Auto-scroll": "Автопрокрутка", "Probe features": "Опрос функций",
    "Copy all": "Копировать всё", "Clear": "Очистить", "Send hex": "Отправить hex",
    "Reading battery…": "Читаем батарею…",
]
