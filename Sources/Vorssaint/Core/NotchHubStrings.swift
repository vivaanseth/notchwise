// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The island's hub on the assistant's page, the dock its hover shows, and
/// the suggestions both make.
struct NotchHubStrings {
    let allPages: String
    let home: String
    let suggested: String
    /// "Suggested: %@", the page's name.
    let suggestedPage: String
    let selection: String
    let summarize: String
    let explain: String
    let improve: String
    let playing: String
    let running: String
    let now: String
    /// "In %d min".
    let startsIn: String
    let downloading: String
    let agents: String
    let watching: String
    let copied: String
    let captured: String
    let resume: String
    /// "Often with %@", the app's name.
    let often: String
    let meeting: String
    let media: String
    let code: String
    let writing: String
    let time: String
    let habit: String
    let suggestionsTitle: String
    let learn: String
    let learnHint: String
    let fitting: String
    let fittingHint: String
    let forget: String
    let forgetTitle: String
    /// The Controls tile that opens every section of the menu panel in the island.
    let allControls: String
    /// The menu panel's switches for the app's features.
    let features: String

    func reason(_ reason: NotchIntentReason, minutes: Int?) -> String {
        switch reason {
        case .live(let signal):
            switch signal {
            case .playing: return playing
            case .timer: return running
            case .meetingSoon: return minutes.map { String(format: startsIn, $0) } ?? now
            case .meetingNow: return now
            case .downloading: return downloading
            case .agents: return agents
            case .watching: return watching
            case .copied: return copied
            case .captured: return captured
            }
        case .resume: return resume
        case .app(let name): return String(format: often, name)
        case .scene(let scene):
            switch scene {
            case .meeting: return meeting
            case .media: return media
            case .code: return code
            case .writing: return writing
            }
        case .time: return time
        case .habit: return habit
        }
    }
}

extension FeatureStrings {
    static func notchHub(_ language: AppLanguage) -> NotchHubStrings {
        switch language {
        case .enUS: return NotchHubStrings(
            allPages: "All pages", home: "Home", suggested: "Suggested", suggestedPage: "Suggested: %@",
            selection: "Selected text",
            summarize: "Summarize", explain: "Explain", improve: "Improve",
            playing: "Playing now", running: "Running", now: "Happening now", startsIn: "In %d min",
            downloading: "Downloading", agents: "Agents at work", watching: "Watching", copied: "Just copied",
            captured: "New capture", resume: "Where you left off", often: "Often with %@",
            meeting: "In a meeting", media: "While watching", code: "While coding", writing: "While writing",
            time: "Usual at this time", habit: "Used often",
            suggestionsTitle: "Suggestions", learn: "Learn which pages I use",
            learnHint: "Ranks the island’s pages by the app in front, the time of day and what’s going on. What it learns stays on this Mac.",
            fitting: "Open on the page that fits",
            fittingHint: "When the app in front or what’s going on clearly points to one page, like AI agents while you code, the island opens there instead of on its home page.",
            forget: "Forget", forgetTitle: "Forget what it learned",
            allControls: "All controls", features: "Features")
        case .ptBR: return NotchHubStrings(
            allPages: "Todas as páginas", home: "Início", suggested: "Sugerida", suggestedPage: "Sugerida: %@",
            selection: "Texto selecionado",
            summarize: "Resumir", explain: "Explicar", improve: "Melhorar",
            playing: "Tocando agora", running: "Em andamento", now: "Acontecendo agora", startsIn: "Em %d min",
            downloading: "Baixando", agents: "Agentes trabalhando", watching: "Observando", copied: "Copiado agora",
            captured: "Nova captura", resume: "Onde você parou", often: "Muito usado com %@",
            meeting: "Em uma reunião", media: "Enquanto assiste", code: "Enquanto programa", writing: "Enquanto escreve",
            time: "Comum neste horário", habit: "Muito usado",
            suggestionsTitle: "Sugestões", learn: "Aprender quais páginas eu uso",
            learnHint: "Ordena as páginas da ilha pelo app em primeiro plano, a hora do dia e o que está acontecendo. O que aprende fica neste Mac.",
            fitting: "Abrir na página certa",
            fittingHint: "Quando o app em primeiro plano ou o que está acontecendo aponta claramente para uma página, como os agentes de IA enquanto você programa, a ilha abre nela em vez da página inicial.",
            forget: "Esquecer", forgetTitle: "Esquecer o que aprendeu",
            allControls: "Todos os controles", features: "Recursos")
        case .tr: return NotchHubStrings(
            allPages: "Tüm sayfalar", home: "Ana sayfa", suggested: "Önerilen", suggestedPage: "Önerilen: %@",
            selection: "Seçili metin",
            summarize: "Özetle", explain: "Açıkla", improve: "İyileştir",
            playing: "Şimdi çalıyor", running: "Çalışıyor", now: "Şu anda", startsIn: "%d dk içinde",
            downloading: "İndiriliyor", agents: "Ajanlar çalışıyor", watching: "İzleniyor", copied: "Az önce kopyalandı",
            captured: "Yeni yakalama", resume: "Kaldığınız yer", often: "Sık sık %@ ile",
            meeting: "Toplantıda", media: "İzlerken", code: "Kod yazarken", writing: "Yazarken",
            time: "Bu saatte olağan", habit: "Sık kullanılan",
            suggestionsTitle: "Öneriler", learn: "Kullandığım sayfaları öğren",
            learnHint: "Adanın sayfalarını öndeki uygulamaya, günün saatine ve olup bitene göre sıralar. Öğrendikleri bu Mac’te kalır.",
            fitting: "Uygun sayfada aç",
            fittingHint: "Öndeki uygulama ya da olup biten açıkça bir sayfayı gösteriyorsa, örneğin kod yazarken yapay zekâ ajanları, ada ana sayfası yerine orada açılır.",
            forget: "Unut", forgetTitle: "Öğrendiklerini unut",
            allControls: "Tüm kontroller", features: "Özellikler")
        case .ru: return NotchHubStrings(
            allPages: "Все страницы", home: "Главная", suggested: "Предложенная", suggestedPage: "Предложено: %@",
            selection: "Выделенный текст",
            summarize: "Кратко", explain: "Объяснить", improve: "Улучшить",
            playing: "Играет сейчас", running: "Идёт", now: "Идёт сейчас", startsIn: "Через %d мин",
            downloading: "Загрузка", agents: "Агенты работают", watching: "Наблюдение", copied: "Только что скопировано",
            captured: "Новый снимок", resume: "Где вы остановились", often: "Часто с %@",
            meeting: "На встрече", media: "Во время просмотра", code: "Во время программирования", writing: "Во время письма",
            time: "Обычно в это время", habit: "Часто используется",
            suggestionsTitle: "Подсказки", learn: "Запоминать, какие страницы я открываю",
            learnHint: "Упорядочивает страницы острова по активному приложению, времени суток и происходящему. Всё изученное остаётся на этом Mac.",
            fitting: "Открывать подходящую страницу",
            fittingHint: "Когда активное приложение или происходящее явно указывает на одну страницу, например ИИ-агенты во время программирования, остров открывается на ней, а не на главной.",
            forget: "Забыть", forgetTitle: "Забыть изученное",
            allControls: "Всё управление", features: "Функции")
        case .es: return NotchHubStrings(
            allPages: "Todas las páginas", home: "Inicio", suggested: "Sugerida", suggestedPage: "Sugerida: %@",
            selection: "Texto seleccionado",
            summarize: "Resumir", explain: "Explicar", improve: "Mejorar",
            playing: "Sonando ahora", running: "En marcha", now: "Ahora mismo", startsIn: "En %d min",
            downloading: "Descargando", agents: "Agentes trabajando", watching: "Vigilando", copied: "Recién copiado",
            captured: "Nueva captura", resume: "Donde lo dejaste", often: "Frecuente con %@",
            meeting: "En una reunión", media: "Mientras ves", code: "Mientras programas", writing: "Mientras escribes",
            time: "Habitual a esta hora", habit: "Muy usado",
            suggestionsTitle: "Sugerencias", learn: "Aprender qué páginas uso",
            learnHint: "Ordena las páginas de la isla según la app en primer plano, la hora del día y lo que está pasando. Lo que aprende se queda en este Mac.",
            fitting: "Abrir en la página adecuada",
            fittingHint: "Cuando la app en primer plano o lo que está pasando apunta claramente a una página, como los agentes de IA mientras programas, la isla se abre ahí en lugar de en su página de inicio.",
            forget: "Olvidar", forgetTitle: "Olvidar lo aprendido",
            allControls: "Todos los controles", features: "Funciones")
        case .sk: return NotchHubStrings(
            allPages: "Všetky stránky", home: "Domov", suggested: "Navrhovaná", suggestedPage: "Navrhované: %@",
            selection: "Označený text",
            summarize: "Zhrnúť", explain: "Vysvetliť", improve: "Vylepšiť",
            playing: "Práve hrá", running: "Beží", now: "Práve prebieha", startsIn: "O %d min",
            downloading: "Sťahuje sa", agents: "Agenti pracujú", watching: "Sleduje sa", copied: "Práve skopírované",
            captured: "Nový záznam", resume: "Kde ste skončili", often: "Často s %@",
            meeting: "Na stretnutí", media: "Pri pozeraní", code: "Pri programovaní", writing: "Pri písaní",
            time: "Obvyklé v tomto čase", habit: "Často používané",
            suggestionsTitle: "Návrhy", learn: "Učiť sa, ktoré stránky používam",
            learnHint: "Zoraďuje stránky ostrova podľa aplikácie v popredí, dennej doby a toho, čo sa deje. Čo sa naučí, zostáva v tomto Macu.",
            fitting: "Otvoriť na vhodnej stránke",
            fittingHint: "Keď aplikácia v popredí alebo to, čo sa deje, jasne ukazuje na jednu stránku, napríklad AI agentov pri programovaní, ostrov sa otvorí na nej namiesto domovskej stránky.",
            forget: "Zabudnúť", forgetTitle: "Zabudnúť naučené",
            allControls: "Všetky ovládače", features: "Funkcie")
        case .de: return NotchHubStrings(
            allPages: "Alle Seiten", home: "Start", suggested: "Vorgeschlagen", suggestedPage: "Vorschlag: %@",
            selection: "Markierter Text",
            summarize: "Zusammenfassen", explain: "Erklären", improve: "Verbessern",
            playing: "Läuft gerade", running: "Läuft", now: "Gerade jetzt", startsIn: "In %d Min.",
            downloading: "Lädt herunter", agents: "Agenten arbeiten", watching: "Beobachtet", copied: "Gerade kopiert",
            captured: "Neue Aufnahme", resume: "Wo du aufgehört hast", often: "Oft mit %@",
            meeting: "In einem Meeting", media: "Beim Schauen", code: "Beim Programmieren", writing: "Beim Schreiben",
            time: "Üblich um diese Zeit", habit: "Oft genutzt",
            suggestionsTitle: "Vorschläge", learn: "Lernen, welche Seiten ich nutze",
            learnHint: "Ordnet die Seiten der Insel nach der App im Vordergrund, der Tageszeit und dem, was gerade passiert. Was es lernt, bleibt auf diesem Mac.",
            fitting: "Auf der passenden Seite öffnen",
            fittingHint: "Wenn die App im Vordergrund oder das, was gerade passiert, klar auf eine Seite zeigt, etwa KI-Agenten beim Programmieren, öffnet sich die Insel dort statt auf ihrer Startseite.",
            forget: "Vergessen", forgetTitle: "Gelerntes vergessen",
            allControls: "Alle Steuerungen", features: "Funktionen")
        case .fr: return NotchHubStrings(
            allPages: "Toutes les pages", home: "Accueil", suggested: "Suggérée", suggestedPage: "Suggestion : %@",
            selection: "Texte sélectionné",
            summarize: "Résumer", explain: "Expliquer", improve: "Améliorer",
            playing: "En lecture", running: "En cours", now: "En ce moment", startsIn: "Dans %d min",
            downloading: "Téléchargement", agents: "Agents au travail", watching: "Surveillance", copied: "Tout juste copié",
            captured: "Nouvelle capture", resume: "Là où vous en étiez", often: "Souvent avec %@",
            meeting: "En réunion", media: "Pendant une vidéo", code: "Pendant le code", writing: "Pendant l’écriture",
            time: "Habituel à cette heure", habit: "Souvent utilisé",
            suggestionsTitle: "Suggestions", learn: "Apprendre les pages que j’utilise",
            learnHint: "Classe les pages de l’île selon l’app au premier plan, l’heure et ce qui se passe. Ce qu’il apprend reste sur ce Mac.",
            fitting: "Ouvrir sur la page qui convient",
            fittingHint: "Quand l’app au premier plan ou ce qui se passe désigne clairement une page, comme les agents IA pendant que vous codez, l’île s’ouvre dessus plutôt que sur sa page d’accueil.",
            forget: "Oublier", forgetTitle: "Oublier ce qui a été appris",
            allControls: "Toutes les commandes", features: "Fonctions")
        case .it: return NotchHubStrings(
            allPages: "Tutte le pagine", home: "Home", suggested: "Suggerita", suggestedPage: "Suggerita: %@",
            selection: "Testo selezionato",
            summarize: "Riassumi", explain: "Spiega", improve: "Migliora",
            playing: "In riproduzione", running: "In corso", now: "In corso ora", startsIn: "Tra %d min",
            downloading: "Download in corso", agents: "Agenti al lavoro", watching: "In osservazione", copied: "Appena copiato",
            captured: "Nuova cattura", resume: "Dove eri rimasto", often: "Spesso con %@",
            meeting: "In riunione", media: "Mentre guardi", code: "Mentre programmi", writing: "Mentre scrivi",
            time: "Solito a quest’ora", habit: "Usato spesso",
            suggestionsTitle: "Suggerimenti", learn: "Impara quali pagine uso",
            learnHint: "Ordina le pagine dell’isola in base all’app in primo piano, all’ora del giorno e a cosa sta succedendo. Ciò che impara resta su questo Mac.",
            fitting: "Apri sulla pagina adatta",
            fittingHint: "Quando l’app in primo piano o ciò che sta succedendo indica chiaramente una pagina, come gli agenti IA mentre programmi, l’isola si apre lì invece che sulla pagina principale.",
            forget: "Dimentica", forgetTitle: "Dimentica ciò che ha imparato",
            allControls: "Tutti i controlli", features: "Funzioni")
        case .ja: return NotchHubStrings(
            allPages: "すべてのページ", home: "ホーム", suggested: "おすすめ", suggestedPage: "おすすめ: %@",
            selection: "選択中のテキスト",
            summarize: "要約", explain: "説明", improve: "改善",
            playing: "再生中", running: "実行中", now: "進行中", startsIn: "%d分後",
            downloading: "ダウンロード中", agents: "エージェントが作業中", watching: "監視中", copied: "コピーしたばかり",
            captured: "新しいキャプチャ", resume: "前回の続き", often: "%@でよく使う",
            meeting: "ミーティング中", media: "視聴中", code: "コーディング中", writing: "執筆中",
            time: "この時間によく使う", habit: "よく使う",
            suggestionsTitle: "候補", learn: "使うページを学習",
            learnHint: "手前のアプリ、時間帯、いま起きていることでアイランドのページを並べ替えます。学習内容はこのMacに残ります。",
            fitting: "合うページで開く",
            fittingHint: "手前のアプリやいま起きていることがはっきり1つのページを示すとき（コーディング中のAIエージェントなど）、アイランドはホームではなくそのページで開きます。",
            forget: "消去", forgetTitle: "学習内容を消去",
            allControls: "すべてのコントロール", features: "機能")
        case .ko: return NotchHubStrings(
            allPages: "모든 페이지", home: "홈", suggested: "추천", suggestedPage: "추천: %@",
            selection: "선택한 텍스트",
            summarize: "요약", explain: "설명", improve: "다듬기",
            playing: "재생 중", running: "실행 중", now: "진행 중", startsIn: "%d분 후",
            downloading: "다운로드 중", agents: "에이전트 작업 중", watching: "감시 중", copied: "방금 복사함",
            captured: "새 캡처", resume: "하던 곳", often: "%@와 자주 사용",
            meeting: "회의 중", media: "시청 중", code: "코딩 중", writing: "글 쓰는 중",
            time: "이 시간에 자주 사용", habit: "자주 사용",
            suggestionsTitle: "제안", learn: "내가 쓰는 페이지 학습",
            learnHint: "앞에 있는 앱, 시간대, 진행 중인 일에 따라 아일랜드의 페이지를 정렬합니다. 학습한 내용은 이 Mac에만 남습니다.",
            fitting: "알맞은 페이지로 열기",
            fittingHint: "앞에 있는 앱이나 진행 중인 일이 한 페이지를 분명히 가리키면(코딩 중의 AI 에이전트 등) 아일랜드가 홈 대신 그 페이지로 열립니다.",
            forget: "지우기", forgetTitle: "학습한 내용 지우기",
            allControls: "모든 제어", features: "기능")
        case .uk: return NotchHubStrings(
            allPages: "Усі сторінки", home: "Головна", suggested: "Запропонована", suggestedPage: "Пропозиція: %@",
            selection: "Виділений текст",
            summarize: "Стисло", explain: "Пояснити", improve: "Покращити",
            playing: "Грає зараз", running: "Триває", now: "Триває зараз", startsIn: "За %d хв",
            downloading: "Завантаження", agents: "Агенти працюють", watching: "Спостереження", copied: "Щойно скопійовано",
            captured: "Новий знімок", resume: "Де ви зупинилися", often: "Часто з %@",
            meeting: "На зустрічі", media: "Під час перегляду", code: "Під час програмування", writing: "Під час письма",
            time: "Зазвичай у цей час", habit: "Часто використовується",
            suggestionsTitle: "Підказки", learn: "Запам’ятовувати, які сторінки я відкриваю",
            learnHint: "Упорядковує сторінки острова за активною програмою, часом доби й тим, що відбувається. Усе вивчене лишається на цьому Mac.",
            fitting: "Відкривати потрібну сторінку",
            fittingHint: "Коли активна програма або те, що відбувається, чітко вказує на одну сторінку, як-от ШІ-агенти під час програмування, острів відкривається на ній, а не на головній.",
            forget: "Забути", forgetTitle: "Забути вивчене",
            allControls: "Усе керування", features: "Функції")
        case .zhHans: return NotchHubStrings(
            allPages: "全部页面", home: "主页", suggested: "推荐", suggestedPage: "推荐：%@",
            selection: "所选文本",
            summarize: "总结", explain: "解释", improve: "润色",
            playing: "正在播放", running: "进行中", now: "正在进行", startsIn: "%d 分钟后",
            downloading: "正在下载", agents: "智能体工作中", watching: "正在监视", copied: "刚刚复制",
            captured: "新截图", resume: "从上次离开处继续", often: "常与 %@ 一起使用",
            meeting: "会议中", media: "观看时", code: "编程时", writing: "写作时",
            time: "这个时段常用", habit: "常用",
            suggestionsTitle: "建议", learn: "学习我使用的页面",
            learnHint: "根据前台 App、时段和正在发生的事情排列灵动岛的页面。学到的内容只保留在这台 Mac 上。",
            fitting: "打开到合适的页面",
            fittingHint: "当前台 App 或正在发生的事明确指向某个页面时（例如编程时的 AI 智能体），灵动岛会直接打开到该页面，而不是主页。",
            forget: "忘记", forgetTitle: "忘记已学内容",
            allControls: "所有控制", features: "功能")
        case .zhTW: return NotchHubStrings(
            allPages: "所有頁面", home: "主頁", suggested: "推薦", suggestedPage: "推薦：%@",
            selection: "選取的文字",
            summarize: "摘要", explain: "解釋", improve: "潤飾",
            playing: "正在播放", running: "進行中", now: "正在進行", startsIn: "%d 分鐘後",
            downloading: "正在下載", agents: "代理工作中", watching: "正在監看", copied: "剛剛拷貝",
            captured: "新截圖", resume: "從上次離開處繼續", often: "常與 %@ 一起使用",
            meeting: "會議中", media: "觀看時", code: "寫程式時", writing: "寫作時",
            time: "這個時段常用", habit: "常用",
            suggestionsTitle: "建議", learn: "學習我使用的頁面",
            learnHint: "依照前景 App、時段和正在發生的事排列動態島的頁面。學到的內容只保留在這台 Mac 上。",
            fitting: "開啟到合適的頁面",
            fittingHint: "當前景 App 或正在發生的事明確指向某個頁面時（例如寫程式時的 AI 代理），動態島會直接開啟到該頁面，而不是主頁。",
            forget: "忘記", forgetTitle: "忘記已學內容",
            allControls: "所有控制項", features: "功能")
        case .zhHK: return NotchHubStrings(
            allPages: "所有頁面", home: "主頁", suggested: "推介", suggestedPage: "推介：%@",
            selection: "揀咗嘅文字",
            summarize: "摘要", explain: "解釋", improve: "潤飾",
            playing: "播緊", running: "進行緊", now: "而家進行緊", startsIn: "%d 分鐘後",
            downloading: "下載緊", agents: "代理工作緊", watching: "監察緊", copied: "啱啱複製咗",
            captured: "新截圖", resume: "由上次停低嘅地方繼續", often: "成日同 %@ 一齊用",
            meeting: "開緊會", media: "睇緊嘢", code: "寫緊程式", writing: "寫緊嘢",
            time: "呢個時段成日用", habit: "成日用",
            suggestionsTitle: "建議", learn: "學習我用開嘅頁面",
            learnHint: "跟前台 App、時段同而家發生緊嘅事排列動態島嘅頁面。學到嘅嘢只會留喺呢部 Mac。",
            fitting: "打開到啱嘅頁面",
            fittingHint: "當前台 App 或者而家發生緊嘅事明顯指向某一頁（例如寫程式時嘅 AI 代理），動態島會直接打開嗰頁，而唔係主頁。",
            forget: "忘記", forgetTitle: "忘記學到嘅嘢",
            allControls: "所有控制項", features: "功能")
        }
    }
}
