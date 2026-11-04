import SwiftUI

/// Shares the existing search-radius preference without issuing network requests.
struct CompanionSearchRadiusControl: View {
    @AppStorage("companionSearchRadius") private var radius = 500.0
    var onEditingChanged: (Bool) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("검색 범위", systemImage: "circle.dashed")
                    .font(.headline)
                Spacer()
                Text("반경 \(Int(radius))m")
                    .font(.headline).monospacedDigit().foregroundStyle(.indigo)
            }
            Slider(value: $radius, in: 100...1000, step: 5, onEditingChanged: onEditingChanged)
                .accessibilityLabel("검색 반경")
                .accessibilityValue("\(Int(radius))미터")
            GeometryReader { geometry in
                ForEach([100, 250, 500, 750, 1000], id: \.self) { value in
                    VStack(spacing: 5) {
                        Rectangle().fill(.secondary.opacity(0.4))
                            .frame(width: 1, height: value == 500 ? 9 : 6)
                        Text(value == 1000 ? "1km" : "\(value)m")
                            .font(.caption2).monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .position(x: 14 + (geometry.size.width - 28) * Double(value - 100) / 900, y: 14)
                }
            }
            .frame(height: 30)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .accessibilityHidden(true)

            Text("5m 단위로 조절하며 다음 AI 추천부터 적용됩니다. 자동으로 요청하지 않아요.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .tint(.indigo)
    }
}

struct CompanionSearchRadiusSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("어디까지 찾아볼까요?").font(.title2.bold())
                    CompanionSearchRadiusControl()
                    Label("지도 탭에서도 같은 범위를 조절하고 원으로 확인할 수 있어요.", systemImage: "map")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(24)
            }
            .navigationTitle("검색 범위")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") { dismiss() }
                }
            }
        }
        .tint(.indigo)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
