// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The VoiceOS assistant as Vorssaint's own surfaces name it: the Features
/// hub, the island's page and strip, and the Settings sidebar. VoiceOS's own
/// pages stay in English, as they were.
struct VoiceAssistantStrings {
    let title: String
    let description: String
    /// The island page and its strip: "Agents" already names the coding
    /// agents' usage, so the voice agent is the Assistant.
    let pageTitle: String
    let editorSummary: String
    /// VoiceOS keeps its name in every language, as the Dynamic Island does.
    var settingsSection: String { "VoiceOS" }
    var searchKeywords: [String] {
        [title, pageTitle, "VoiceOS", "dictation", "voice", "Jarvis", "Ollama", "Claude"]
    }
}

extension FeatureStrings {
    static func voiceAssistant(_ language: AppLanguage) -> VoiceAssistantStrings {
        switch language {
        case .enUS: return VoiceAssistantStrings(
            title: "Voice Assistant",
            description: "Talk to your Mac from the Dynamic Island: hold right ⌘ to ask, or hold fn anywhere to dictate. A model on this Mac answers first; a cloud AI only when a request needs one.",
            pageTitle: "Assistant",
            editorSummary: "Ask by voice or by typing, with answers read aloud.")
        case .ptBR: return VoiceAssistantStrings(
            title: "Assistente de voz",
            description: "Fale com o seu Mac pela Dynamic Island: segure ⌘ direito para perguntar ou segure fn em qualquer lugar para ditar. Um modelo neste Mac responde primeiro; uma IA na nuvem só quando o pedido precisa.",
            pageTitle: "Assistente",
            editorSummary: "Pergunte por voz ou digitando, com respostas lidas em voz alta.")
        case .tr: return VoiceAssistantStrings(
            title: "Sesli Asistan",
            description: "Dynamic Island’dan Mac’inizle konuşun: sormak için sağ ⌘ tuşunu, her yerde dikte için fn tuşunu basılı tutun. Önce bu Mac’teki model yanıtlar; bulut yapay zekâsı yalnızca gerektiğinde.",
            pageTitle: "Asistan",
            editorSummary: "Sesle ya da yazarak sorun, yanıtlar sesli okunur.")
        case .ru: return VoiceAssistantStrings(
            title: "Голосовой ассистент",
            description: "Говорите с Mac через Dynamic Island: удерживайте правую ⌘, чтобы спросить, или fn, чтобы диктовать где угодно. Сначала отвечает модель на этом Mac, а облачный ИИ только когда он нужен.",
            pageTitle: "Ассистент",
            editorSummary: "Спрашивайте голосом или текстом, ответы читаются вслух.")
        case .es: return VoiceAssistantStrings(
            title: "Asistente de voz",
            description: "Habla con tu Mac desde la Dynamic Island: mantén ⌘ derecha para preguntar o fn en cualquier lugar para dictar. Primero responde un modelo en este Mac; una IA en la nube solo cuando hace falta.",
            pageTitle: "Asistente",
            editorSummary: "Pregunta con la voz o escribiendo, con respuestas en voz alta.")
        case .sk: return VoiceAssistantStrings(
            title: "Hlasový asistent",
            description: "Hovorte so svojím Macom z Dynamic Island: podržte pravý ⌘ a pýtajte sa, alebo podržte fn kdekoľvek a diktujte. Najprv odpovedá model v tomto Macu, cloudová AI len vtedy, keď je potrebná.",
            pageTitle: "Asistent",
            editorSummary: "Pýtajte sa hlasom alebo písaním, odpovede zaznejú nahlas.")
        case .de: return VoiceAssistantStrings(
            title: "Sprachassistent",
            description: "Sprich mit deinem Mac über die Dynamic Island: Halte die rechte ⌘-Taste, um zu fragen, oder fn, um überall zu diktieren. Zuerst antwortet ein Modell auf diesem Mac, eine Cloud-KI nur, wenn eine Anfrage sie braucht.",
            pageTitle: "Assistent",
            editorSummary: "Frag per Stimme oder Tastatur, die Antworten werden vorgelesen.")
        case .fr: return VoiceAssistantStrings(
            title: "Assistant vocal",
            description: "Parlez à votre Mac depuis la Dynamic Island : maintenez ⌘ droite pour demander, ou fn n’importe où pour dicter. Un modèle sur ce Mac répond d’abord ; une IA dans le cloud seulement si la demande l’exige.",
            pageTitle: "Assistant",
            editorSummary: "Demandez à la voix ou au clavier, avec des réponses lues à voix haute.")
        case .it: return VoiceAssistantStrings(
            title: "Assistente vocale",
            description: "Parla con il tuo Mac dalla Dynamic Island: tieni premuto ⌘ destro per chiedere o fn ovunque per dettare. Prima risponde un modello su questo Mac, un’IA nel cloud solo quando serve.",
            pageTitle: "Assistente",
            editorSummary: "Chiedi a voce o scrivendo, con risposte lette ad alta voce.")
        case .ja: return VoiceAssistantStrings(
            title: "音声アシスタント",
            description: "Dynamic Island から Mac に話しかけられます。右 ⌘ を長押しして質問、fn を長押ししてどこでも音声入力。まずこの Mac のモデルが答え、必要なときだけクラウド AI を使います。",
            pageTitle: "アシスタント",
            editorSummary: "声または入力で質問でき、答えは読み上げられます。")
        case .ko: return VoiceAssistantStrings(
            title: "음성 비서",
            description: "Dynamic Island에서 Mac에 말을 걸어 보세요. 오른쪽 ⌘를 길게 눌러 질문하고, fn을 길게 눌러 어디서나 받아쓰기합니다. 먼저 이 Mac의 모델이 답하고, 필요할 때만 클라우드 AI를 씁니다.",
            pageTitle: "비서",
            editorSummary: "음성이나 입력으로 묻고, 답을 소리 내어 들을 수 있습니다.")
        case .uk: return VoiceAssistantStrings(
            title: "Голосовий асистент",
            description: "Говоріть з Mac через Dynamic Island: утримуйте праву ⌘, щоб запитати, або fn, щоб диктувати будь-де. Спершу відповідає модель на цьому Mac, а хмарний ШІ лише коли він потрібен.",
            pageTitle: "Асистент",
            editorSummary: "Питайте голосом або текстом, відповіді звучать уголос.")
        case .zhHans: return VoiceAssistantStrings(
            title: "语音助理",
            description: "在 Dynamic Island 中与 Mac 对话：按住右侧 ⌘ 提问，或在任意位置按住 fn 听写。优先由这台 Mac 上的模型回答，只在需要时才使用云端 AI。",
            pageTitle: "助理",
            editorSummary: "用语音或打字提问，回答会朗读出来。")
        case .zhTW: return VoiceAssistantStrings(
            title: "語音助理",
            description: "在 Dynamic Island 中與 Mac 對話：按住右側 ⌘ 提問，或在任何地方按住 fn 聽寫。優先由這台 Mac 上的模型回答，只在需要時才使用雲端 AI。",
            pageTitle: "助理",
            editorSummary: "用語音或打字提問，回答會朗讀出來。")
        case .zhHK: return VoiceAssistantStrings(
            title: "語音助理",
            description: "喺 Dynamic Island 同 Mac 對話：㩒住右邊 ⌘ 發問，或者喺任何地方㩒住 fn 聽寫。優先由呢部 Mac 上面嘅模型回答，有需要先至用雲端 AI。",
            pageTitle: "助理",
            editorSummary: "用語音或者打字發問，答案會讀出嚟。")
        }
    }
}
