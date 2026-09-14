import SwiftUI

struct LensControls: View {
    @ObservedObject var model: LensModel
    let onToggle: () -> Void
    let onLock: () -> Void
    let onPrepare: () -> Void
    let onReader: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("원문", selection: $model.source) {
                    Text("자동").tag(nil as LensLanguage?)
                    ForEach(LensLanguage.allCases) { Text($0.title).tag(Optional($0)) }
                }.frame(width: 175)
                Image(systemName: "arrow.right")
                Picker("번역", selection: $model.target) { ForEach(LensLanguage.allCases) { Text($0.title).tag($0) } }.frame(width: 165)
                Spacer()
                Button(model.running ? "일시정지" : (model.permissionNeeded ? "화면 권한 확인" : "다시 시작"), action: onToggle)
                Toggle("잠금", isOn: $model.locked).onChange(of: model.locked) { _, _ in onLock() }
            }
            HStack {
                Picker("표시", selection: $model.reproduced) { Text("화면 재현").tag(true); Text("투명").tag(false) }.frame(width: 200)
                Text("원문 가림")
                Slider(value: $model.opacity, in: 0...1).frame(width: 130).accessibilityLabel("원문 가림 불투명도")
                Text("\(Int(model.opacity * 100))%").monospacedDigit().frame(width: 36)
                Spacer(); Button("전문 보기", action: onReader); Button("언어 준비", action: onPrepare)
            }
            Text(model.status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.padding(14).frame(minWidth: 750)
    }
}

struct TranslationReader: View {
    @ObservedObject var model: LensModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("전체 번역").font(.title2)
                if model.translations.isEmpty { Text("렌즈에 번역된 텍스트가 표시되면 여기서 전문을 볼 수 있습니다.").foregroundStyle(.secondary) }
                ForEach(model.translations) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.block.text).font(.callout).foregroundStyle(.secondary)
                        Text(item.text).font(.body)
                    }; Divider()
                }
                Text(model.metrics).font(.caption).foregroundStyle(.secondary)
                Text("시간은 앱 내부 측정이며 실제 화면 표시 지연과 다를 수 있습니다.").font(.caption2).foregroundStyle(.secondary)
            }.textSelection(.enabled).padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
