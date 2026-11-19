# OnePlus Buds for Windows (WPF) — fork with extras

Windows companion for OnePlus Buds 4 / Buds Pro 3, based on [Thomaspatrick14/Oneplus-buds-Win-Companion](https://github.com/Thomaspatrick14/Oneplus-buds-Win-Companion) (MIT, original license kept in `LICENSE`). It is the Windows counterpart of the macOS app in this repository.

## Что добавлено / What's added

- **Русский и English** — язык определяется по системе, переключается в меню значка в трее. / Auto-detected UI language, switch from the tray menu.
- **Всплывающее окно при подключении** — карточка с зарядом левого/правого наушника и кейса вместо стандартного уведомления. / Connect popup with battery levels.
- **Всплывашка смены режима шумоподавления** (ANC / прозрачность / адаптивный / выкл), в том числе при жесте на наушнике. / Popup on noise-mode change, including earbud gestures.
- **Расширенный список устройств** — OnePlus Buds, Nord Buds, OPPO Enco (протокол HeyMelody). Проверено только на Buds 4 и Pro 3. / Wider device list; verified on Buds 4 / Pro 3 only.

Остальной функционал (ANC, EQ, BassWave, свой EQ, жесты, лог пакетов) — как в оригинале. / Everything else is as upstream.

## Сборка / Build

Требуется .NET 8 SDK и Windows. / Needs the .NET 8 SDK on Windows.

```
dotnet build windows/OnePlusBuds4/OnePlusBuds4.csproj -c Release
```

Готовая сборка (нужен .NET 8 Desktop Runtime): раздел Releases. / Prebuilt zip (requires .NET 8 Desktop Runtime): see Releases.

> Сборка получена кросс-компиляцией, на реальном Windows с наушниками не проверялась — сообщайте о проблемах в Issues. / Cross-compiled, not yet tested on a real Windows machine with earbuds.
