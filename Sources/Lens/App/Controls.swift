import SwiftUI

enum LensSettingsPage: String, CaseIterable, Identifiable {
    case translation, appearance, capture
    var id: String { rawValue }
    var title: String {
        switch self { case .translation: "번역"; case .appearance: "표시"; case .capture: "캡처" }
    }
    var symbol: String {
        switch self { case .translation: "character.bubble"; case .appearance: "viewfinder"; case .capture: "camera" }
    }
}

@MainActor final class LensSettingsSelection: ObservableObject {
    @Published var page: LensSettingsPage = .translation
}

struct LensControls: View {
    @ObservedObject var model: LensModel
    @ObservedObject var languages: LanguageCatalog
    @ObservedObject var recording: LensRecording
    @ObservedObject var selection: LensSettingsSelection
    let onToggle: () -> Void
    let onLock: () -> Void
    let onPrepare: () -> Void
    let onReader: () -> Void
    let onCapture: () -> Void
    let onRecord: () -> Void
    let onPermissionSettings: () -> Void

    var body: some View {
        Form {
            switch selection.page {
            case .translation: translation
            case .appearance: appearance
            case .capture: capture
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 440)
    }

    private var translation: some View {
        Group {
            if model.permissionNeeded {
                Section {
                    Label("화면 기록 접근이 필요합니다", systemImage: "lock.shield")
                        .font(.headline)
                    Text("렌즈 뒤의 텍스트를 읽으려면 시스템 설정에서 Lens를 허용하세요.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("시스템 설정 열기…", action: onPermissionSettings)
                        Button("다시 확인", action: onToggle)
                    }
                } footer: {
                    Text("이미 허용했다면 Lens를 종료한 뒤 다시 여세요. 앱을 새 빌드로 교체하면 다시 허용해야 할 수 있습니다.")
                }
            }
            Section {
                Picker("원문 언어", selection: $model.source) {
                    Text("자동 감지").tag(nil as LensLanguage?)
                    Divider()
                    ForEach(languages.sourceLanguages) { Text($0.title).tag(Optional($0)) }
                    if let source = model.source, !languages.sourceLanguages.contains(source) {
                        Text("\(source.title) · 화면 인식 미지원").tag(Optional(source)).disabled(true)
                    }
                }
                Picker("번역 언어", selection: $model.targetPreference) {
                    Text("macOS 언어 사용 (\(LensLanguage.systemDefault(supported: languages.languages).title))").tag(nil as LensLanguage?)
                    Divider()
                    ForEach(languages.languages) { Text($0.title).tag(Optional($0)) }
                    if let target = model.targetPreference, !languages.languages.contains(target) {
                        Text("\(target.title) · 지원 여부 확인 필요").tag(Optional(target))
                    }
                }
            } header: { Text("언어") } footer: {
                Text("macOS의 번역 지원 언어를 표시합니다. 원문 목록은 화면 인식이 가능한 언어로 제한됩니다. 짧은 단어나 이름은 원문 언어를 직접 선택하세요.")
            }
            Section {
                LabeledContent("기기 내 번역") {
                    Button("언어 팩 관리…", action: onPrepare)
                }
                if languages.loading {
                    ProgressView("사용 가능한 언어 확인 중…").controlSize(.small)
                } else if let error = languages.error {
                    Text("화면 인식 언어를 확인하지 못했습니다: \(error)").foregroundStyle(.secondary)
                } else if model.source?.isSameLanguage(as: model.target) == true {
                    Text("원문과 번역 언어가 같습니다.").foregroundStyle(.secondary)
                } else if let source = model.source, let route = languages.route(from: source, to: model.target) {
                    Label(route.status == .installed ? "선택한 언어로 번역할 수 있습니다" : "언어 팩 관리에서 준비 상태를 확인하세요",
                          systemImage: route.status == .installed ? "checkmark.circle" : "arrow.down.circle")
                } else {
                    Text("\(model.target.title)로 바로 번역 가능한 원문 \(languages.sourceLanguages.filter { languages.route(from: $0, to: model.target)?.status == .installed }.count)개")
                        .foregroundStyle(.secondary)
                }
            } footer: { Text("설치된 빠른 번역 모델을 우선 사용하고, 필요한 경우 준비된 Apple Intelligence 모델을 사용합니다. 언어를 자동으로 다운로드하지 않습니다.") }
            Section {
                LabeledContent {
                    Button(model.running ? "일시정지" : "번역 시작", action: onToggle)
                        .disabled(model.permissionNeeded)
                } label: {
                    Label(model.permissionNeeded ? "권한 필요" : (model.running ? "번역 중" : "일시정지됨"),
                          systemImage: model.permissionNeeded ? "exclamationmark.circle" : (model.running ? "play.circle" : "pause.circle"))
                }
                if !model.permissionNeeded {
                    Text(model.status).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: { Text("현재 상태") }
        }
    }

    private var appearance: some View {
        Group {
            Section {
                Picker("배경", selection: $model.reproduced) {
                    Text("화면 재현").tag(true)
                    Text("투명").tag(false)
                }.pickerStyle(.segmented)
                Text(model.reproduced
                    ? "캡처한 뒤 화면과 번역을 렌즈 안에 함께 표시합니다."
                    : "실제 뒤 화면은 그대로 비추고 번역만 위에 표시합니다.")
                    .foregroundStyle(.secondary)
            } header: { Text("렌즈 배경") } footer: { Text("두 모드 모두 렌즈 테두리는 유지됩니다.") }
            Section {
                LabeledContent("원문 가리기") {
                    Text(model.opacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.opacity, in: 0...1) {
                    Text("원문 가리기")
                } minimumValueLabel: { Text("0%") } maximumValueLabel: { Text("100%") }
                .labelsHidden()
                .accessibilityValue("\(Int(model.opacity * 100))퍼센트")
            } footer: { Text("번역 뒤의 원문을 배경색으로 덮는 정도입니다. 번역 글자의 투명도는 바뀌지 않습니다.") }
            Section {
                Toggle("클릭과 스크롤 통과", isOn: $model.locked)
                    .onChange(of: model.locked) { _, _ in onLock() }
            } header: { Text("마우스") } footer: {
                Text("켜면 렌즈 뒤의 앱을 조작할 수 있습니다. 렌즈를 이동하거나 크기를 바꾸려면 끄세요. 메뉴 막대에서도 전환할 수 있습니다.")
            }
        }
    }

    private var capture: some View {
        Group {
            if !model.hasFrame && !recording.isRecording {
                Section {
                    Label("화면이 연결되면 저장할 수 있습니다", systemImage: "info.circle")
                    Button("번역 설정 보기") { selection.page = .translation }
                }
            }
            Section {
                LabeledContent("PNG 이미지") {
                    Button("이미지 저장…", action: onCapture).disabled(!model.hasFrame)
                }
            } header: { Text("이미지") } footer: { Text("지금 렌즈에 보이는 화면과 번역을 한 장의 이미지로 저장합니다.") }
            Section {
                LabeledContent("MP4 동영상", value: "최대 15fps · 소리 없음")
                HStack {
                    if recording.isRecording {
                        Label("녹화 중 \(recording.durationText)", systemImage: "record.circle")
                            .foregroundStyle(.red).monospacedDigit()
                    } else if recording.isFinishing {
                        ProgressView().controlSize(.small)
                        Text("동영상 저장 중…")
                    }
                    Spacer()
                    Button(recording.isRecording ? "녹화 중지 및 저장" : "녹화 시작…", action: onRecord)
                        .disabled(recording.isFinishing || (!recording.isRecording && !model.hasFrame))
                }
                if !recording.isRecording && !recording.isFinishing && recording.elapsed > 0 {
                    Text(recording.message).foregroundStyle(.secondary)
                }
            } header: { Text("동영상") } footer: {
                Text("렌즈 이동·크기 변경, 번역 언어 변경, 일시정지 또는 앱 종료 시 녹화를 마치고 저장합니다. 설정을 닫아도 녹화는 계속됩니다.")
            }
            Section {
                Label("투명 모드에서도 뒤 화면이 저장됩니다", systemImage: "rectangle.on.rectangle")
                Text("제목 표시줄과 Lens의 다른 창은 포함하지 않습니다. 저장할 때마다 위치를 선택합니다.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TranslationReader: View {
    @ObservedObject var model: LensModel
    let onShowLens: () -> Void
    let onSettings: () -> Void
    @State private var showOriginal = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.translations.count)개 번역").foregroundStyle(.secondary)
                Spacer()
                Toggle("원문 표시", isOn: $showOriginal).toggleStyle(.checkbox)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(model.translations.map(\.text).joined(separator: "\n\n"), forType: .string)
                } label: { Label("모두 복사", systemImage: "doc.on.doc") }
                .disabled(model.translations.isEmpty)
            }.padding(16)
            Divider()
            if model.translations.isEmpty {
                ContentUnavailableView {
                    Label("아직 번역이 없습니다", systemImage: "character.bubble")
                } description: {
                    Text(model.permissionNeeded ? "화면 기록 접근을 허용한 뒤 렌즈를 텍스트 위에 놓으세요." : "렌즈를 텍스트 위에 놓으면 잘린 번역도 여기에서 모두 읽을 수 있습니다.")
                } actions: {
                    Button(model.permissionNeeded ? "설정 열기…" : "렌즈 보기", action: model.permissionNeeded ? onSettings : onShowLens)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.translations) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                if showOriginal { Text(item.block.text).foregroundStyle(.secondary) }
                                Text(item.text).font(.body)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .contextMenu {
                                    Button("번역 복사") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(item.text, forType: .string)
                                    }
                                }
                            Divider()
                        }
                    }.padding(24)
                }
            }
        }.background(Color(nsColor: .windowBackgroundColor))
    }
}

struct LensHelpView: View {
    var body: some View {
        Form {
            Section("화면 위에서 번역하기") {
                Text("1. 설정에서 화면 기록 접근과 언어 팩을 준비하세요.")
                Text("2. 렌즈를 텍스트 위에 놓고 크기를 맞추세요.")
                Text("3. 뒤의 앱을 조작하려면 ‘클릭과 스크롤 통과’를 켜세요.")
            }
            Section("단축키") {
                LabeledContent("설정", value: "⌘,")
                LabeledContent("렌즈 보기", value: "⌘L")
                LabeledContent("번역 시작 / 일시정지", value: "⌘R")
                LabeledContent("클릭과 스크롤 통과", value: "⌘K")
                LabeledContent("번역 전문", value: "⌘T")
                LabeledContent("이미지 저장", value: "⇧⌘S")
                LabeledContent("녹화 시작 / 중지", value: "⇧⌘R")
                Text("Lens가 활성화되어 있을 때 사용할 수 있습니다. 다른 앱을 사용 중이면 메뉴 막대의 Lens 아이콘을 이용하세요.").foregroundStyle(.secondary)
            }
            Section("개인정보와 저장") {
                Text("화면 인식과 번역은 기기에서 처리합니다. 이미지·동영상은 직접 저장을 요청할 때만 파일로 남으며, 오디오는 녹음하지 않습니다.")
                Text("녹화 중에는 메뉴 막대에 녹화 상태가 표시됩니다. 강제 종료하면 영상이 정상적으로 저장되지 않을 수 있습니다.")
            }
        }.formStyle(.grouped).frame(minWidth: 460, minHeight: 500)
    }
}
