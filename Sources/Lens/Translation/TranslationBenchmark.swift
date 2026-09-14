import Foundation

/// Authored reference candidates, not human-validated acceptance criteria.
struct TranslationBenchmarkSentence: Sendable {
    let number: Int
    let category: String
    let korean: String
    let japanese: String
    let english: String
    func text(in language: LensLanguage) -> String {
        switch language { case .korean: korean; case .japanese: japanese; case .english: english }
    }
}

enum TranslationBenchmark {
    static let corpus: [TranslationBenchmarkSentence] = [
        .init(number: 1, category: "numbers", korean: "회의는 14시 30분에 시작합니다.", japanese: "会議は14時30分に始まります。", english: "The meeting starts at 14:30."),
        .init(number: 2, category: "numbers", korean: "파일 12개 중 3개를 선택했습니다.", japanese: "12個のファイルのうち3個を選択しました。", english: "You selected 3 of 12 files."),
        .init(number: 3, category: "numbers", korean: "배터리가 15% 남았습니다.", japanese: "バッテリー残量は15%です。", english: "The battery has 15% remaining."),
        .init(number: 4, category: "numbers", korean: "온도는 영하 5도입니다.", japanese: "気温はマイナス5度です。", english: "The temperature is minus 5 degrees."),
        .init(number: 5, category: "numbers", korean: "버전 2.4.1에는 수정 사항이 7개 있습니다.", japanese: "バージョン2.4.1には7件の修正があります。", english: "Version 2.4.1 contains 7 fixes."),
        .init(number: 6, category: "numbers", korean: "2026년 9월 14일까지 제출해 주세요.", japanese: "2026年9月14日までに提出してください。", english: "Please submit by September 14, 2026."),
        .init(number: 7, category: "negation", korean: "이 파일을 삭제하지 마세요.", japanese: "このファイルを削除しないでください。", english: "Do not delete this file."),
        .init(number: 8, category: "negation", korean: "변경 사항은 아직 저장되지 않았습니다.", japanese: "変更はまだ保存されていません。", english: "The changes have not been saved yet."),
        .init(number: 9, category: "negation", korean: "알림을 꺼도 메시지는 삭제되지 않습니다.", japanese: "通知をオフにしてもメッセージは削除されません。", english: "Turning off notifications does not delete messages."),
        .init(number: 10, category: "negation", korean: "모든 사용자가 관리자 권한을 가진 것은 아닙니다.", japanese: "すべてのユーザーが管理者権限を持っているわけではありません。", english: "Not every user has administrator privileges."),
        .init(number: 11, category: "negation", korean: "인터넷에 연결하지 않으면 언어 팩을 다운로드할 수 없습니다.", japanese: "インターネットに接続しないと言語パックをダウンロードできません。", english: "You cannot download language packs without an internet connection."),
        .init(number: 12, category: "negation", korean: "취소해도 이전에 저장한 설정은 바뀌지 않습니다.", japanese: "キャンセルしても以前に保存した設定は変わりません。", english: "Canceling does not change previously saved settings."),
        .init(number: 13, category: "ui", korean: "계속하려면 화면 공유를 허용해 주세요.", japanese: "続行するには画面共有を許可してください。", english: "Allow screen sharing to continue."),
        .init(number: 14, category: "ui", korean: "원본 언어와 번역 언어를 선택하세요.", japanese: "原文の言語と翻訳先の言語を選択してください。", english: "Select the source and target languages."),
        .init(number: 15, category: "ui", korean: "다시 시도하려면 여기를 누르세요.", japanese: "再試行するにはここを押してください。", english: "Press here to try again."),
        .init(number: 16, category: "ui", korean: "검색 결과가 없습니다.", japanese: "検索結果はありません。", english: "No search results were found."),
        .init(number: 17, category: "ui", korean: "창을 닫기 전에 변경 사항을 저장하시겠습니까?", japanese: "ウィンドウを閉じる前に変更を保存しますか？", english: "Would you like to save changes before closing the window?"),
        .init(number: 18, category: "ui", korean: "다운로드를 일시 정지했습니다.", japanese: "ダウンロードを一時停止しました。", english: "The download has been paused."),
        .init(number: 19, category: "paragraph", korean: "언어 팩 설치가 끝났습니다. 이제 연결이 끊겨도 번역할 수 있습니다.", japanese: "言語パックのインストールが完了しました。これで接続が切れても翻訳できます。", english: "Language pack installation is complete. You can now translate even if the connection is lost."),
        .init(number: 20, category: "paragraph", korean: "선택한 영역만 캡처합니다. 다른 창의 내용은 포함하지 않습니다.", japanese: "選択した領域だけをキャプチャします。他のウィンドウの内容は含めません。", english: "Only the selected area is captured. Content from other windows is not included."),
        .init(number: 21, category: "paragraph", korean: "작업을 완료하지 못했습니다. 연결을 확인한 후 다시 시도해 주세요.", japanese: "処理を完了できませんでした。接続を確認してから再試行してください。", english: "The operation could not be completed. Check the connection and try again."),
        .init(number: 22, category: "paragraph", korean: "첫 번째 줄을 읽어 주세요.\n두 번째 줄에는 추가 설명이 있습니다.", japanese: "最初の行を読んでください。\n2行目には追加の説明があります。", english: "Please read the first line.\nThe second line contains additional information."),
        .init(number: 23, category: "paragraph", korean: "초대 링크는 24시간 동안 유효합니다. 만료되면 새 링크를 요청하세요.", japanese: "招待リンクは24時間有効です。期限が切れたら新しいリンクを申請してください。", english: "The invitation link is valid for 24 hours. Request a new link after it expires."),
        .init(number: 24, category: "paragraph", korean: "자동 저장이 켜져 있습니다. 마지막 저장 시간은 오전 9시입니다.", japanese: "自動保存が有効です。最後の保存時刻は午前9時です。", english: "Autosave is enabled. The last save was at 9 AM."),
        .init(number: 25, category: "properNames", korean: "민수는 도쿄역에서 유키를 만났습니다.", japanese: "ミンスは東京駅でユキに会いました。", english: "Minsu met Yuki at Tokyo Station."),
        .init(number: 26, category: "properNames", korean: "김지수에게 보고서를 보내 주세요.", japanese: "キム・ジスに報告書を送ってください。", english: "Please send the report to Kim Jisu."),
        .init(number: 27, category: "properNames", korean: "Lens는 한국어, 일본어, 영어를 지원합니다.", japanese: "Lensは韓国語、日本語、英語に対応しています。", english: "Lens supports Korean, Japanese, and English."),
        .init(number: 28, category: "properNames", korean: "Apple 계정으로 로그인하세요.", japanese: "Appleアカウントでサインインしてください。", english: "Sign in with your Apple Account."),
        .init(number: 29, category: "properNames", korean: "서울에서 오사카까지 가는 표를 예약했습니다.", japanese: "ソウルから大阪までのチケットを予約しました。", english: "I booked a ticket from Seoul to Osaka."),
        .init(number: 30, category: "properNames", korean: "Alex와 사토 씨는 부산에서 프로젝트를 발표합니다.", japanese: "Alexと佐藤さんは釜山でプロジェクトを発表します。", english: "Alex and Sato will present the project in Busan.")
    ]

    struct Result: Sendable {
        let sentenceNumber: Int
        let source: LensLanguage
        let target: LensLanguage
        let input: String
        let reference: String
        let output: String
    }

    /// Runs 180 translations. Returns raw outputs for review, never an acceptance score.
    /// Uses the supplied engine's current cache; does not prepare or download models.
    @MainActor
    static func run(engine: any TranslationEngine) async throws -> [Result] {
        var results: [Result] = []
        for pair in TranslationPair.allDirections {
            try Task.checkCancellation()
            let inputs = corpus.map {
                TranslationInput(id: UUID(), text: $0.text(in: pair.source), source: pair.source, target: pair.target)
            }
            let outputs = try await engine.translate(inputs)
            try Task.checkCancellation()
            guard outputs.count == inputs.count,
                  zip(inputs, outputs).allSatisfy({ $0.id == $1.id }) else {
                throw AppleTranslationEngine.Failure.invalidResponse
            }
            for (sentence, output) in zip(corpus, outputs) {
                results.append(Result(sentenceNumber: sentence.number, source: pair.source, target: pair.target,
                                      input: sentence.text(in: pair.source), reference: sentence.text(in: pair.target),
                                      output: output.text))
            }
        }
        return results
    }
}
