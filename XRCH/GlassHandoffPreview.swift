#if DEBUG
import MapKit
import SwiftUI

/// Isolated UI prototype. Never creates an auth session or accesses the location/BLE bridge.
struct GlassHandoffPreview: View {
    @State private var isConnecting = false
    @State private var displayAfterConnection = false
    @State private var connected = false
    @State private var sent = false
    @State private var saved = false

    private let coordinate = CLLocationCoordinate2D(latitude: 37.3017, longitude: 126.8386)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Label("디자인 미리보기 · 실제 장소·연결 정보가 아닙니다", systemImage: "testtube.2")
                        .font(.caption).foregroundStyle(.secondary)

                    mapPreview

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("AI가 고른 장소", systemImage: "sparkles")
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.indigo)
                            Spacer()
                            Text("카페").font(.caption.weight(.medium))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(.quaternary, in: Capsule())
                        }
                        Text("온유 커피").font(.largeTitle.bold())
                        Text("잠깐 쉬어 가거나, 조용히 집중하고 싶을 때")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 18) { placeFacts }
                            VStack(alignment: .leading, spacing: 8) { placeFacts }
                        }
                        .font(.subheadline)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Label("이런 점이 잘 맞아요", systemImage: "sparkles")
                            .font(.headline)
                        Text("“근처에서 조용히 작업할 카페”라는 질문에 맞춰 고른 예시예요.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        reason("speaker.slash", "조용한 분위기", "큰길에서 한 블록 안쪽, 대화와 작업에 편안한 공간")
                        reason("laptopcomputer", "혼자 머물기 편한 자리", "노트북을 놓기 좋은 테이블과 창가 좌석")
                        reason("figure.walk", "부담 없는 거리", "현재 위치에서 약 350m, 걸어서 약 5분")
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.indigo.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("글라스로 이어보기").font(.headline)
                            Spacer()
                            Text(isConnecting ? "연결 중… · 모의" : connected ? "연결됨 · 모의" : "연결 필요")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(connected ? Color.green : Color.secondary)
                        }
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "vision.pro")
                                .font(.title).foregroundStyle(.indigo)
                                .frame(width: 56, height: 56)
                                .background(.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("휴대폰은 내려두고, 장소는 눈앞에")
                                    .font(.subheadline.weight(.semibold))
                                Text("장소 이름과 위치를 글라스에 표시하는 화면입니다. 경로 안내를 시작하지는 않아요.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                        Label("표시할 장소 · 온유 커피 1곳", systemImage: "mappin.circle")
                            .font(.subheadline)
                        if connected {
                            Label("Meta Quest 3 연결됨 · 모의", systemImage: "checkmark.circle.fill")
                                .font(.subheadline).foregroundStyle(.green)
                        } else {
                            Button {
                                displayAfterConnection = false
                                isConnecting = true
                            } label: {
                                HStack(spacing: 10) {
                                    if isConnecting { ProgressView() }
                                    Label(isConnecting ? "글라스에 연결하는 중…" : "글라스 연결하기",
                                          systemImage: "wave.3.right")
                                    Spacer(minLength: 0)
                                }
                                .frame(minHeight: 44)
                            }
                            .disabled(isConnecting)
                        }
                        if sent {
                            Label("온유 커피를 글라스에 표시했어요 · 모의", systemImage: "mappin.circle.fill")
                                .font(.subheadline).foregroundStyle(.indigo)
                        }
                    }
                    .padding(18)
                    .background(.background, in: RoundedRectangle(cornerRadius: 20))

                    HStack(spacing: 12) {
                        Button { saved.toggle() } label: {
                            Label(saved ? "저장됨 · 모의" : "저장", systemImage: saved ? "heart.fill" : "heart")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        Button {} label: {
                            Label("지도 보기", systemImage: "map")
                                .frame(maxWidth: .infinity, minHeight: 32)
                        }
                        .disabled(true)
                    }
                    .buttonStyle(.bordered)
                    Text("이 화면의 장소·거리·추천 이유는 UI 확인을 위한 예시입니다. 저장과 연결도 이 화면 안에서만 바뀝니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("추천 장소")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button {
                        if connected {
                            sent = true
                        } else {
                            displayAfterConnection = true
                            isConnecting = true
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if isConnecting { ProgressView().tint(.white) }
                            Label(sent ? "글라스에 표시했어요 · 모의"
                                  : isConnecting ? "글라스에 연결하는 중…"
                                  : connected ? "글라스에 장소 표시" : "연결하고 장소 표시",
                                  systemImage: sent ? "checkmark.circle.fill" : "vision.pro")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnecting || sent)
                    Text(sent ? "실제 BLE 패킷은 전송하지 않았습니다" : "미리보기에서는 실제 연결·전송이 일어나지 않습니다")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
                .background(.regularMaterial)
            }
            .task(id: isConnecting) {
                guard isConnecting else { return }
                do {
                    try await Task.sleep(for: .seconds(1.2))
                    connected = true
                    if displayAfterConnection { sent = true }
                    isConnecting = false
                } catch {
                    // Leaving this preview cancels the simulated connection.
                    isConnecting = false
                }
            }
        }
        .tint(.indigo)
    }

    private var mapPreview: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.006, longitudeDelta: 0.006))), interactionModes: []) {
            Annotation("온유 커피 · 예시", coordinate: coordinate) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.title3).foregroundStyle(.white)
                    .padding(12).background(.indigo, in: Circle())
            }
        }
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .bottomLeading) {
            Label("ERICA 인근 · 예시 위치", systemImage: "mappin")
                .font(.caption.weight(.medium)).padding(10)
                .background(.regularMaterial, in: Capsule()).padding(12)
        }
        .accessibilityLabel("추천 장소의 예시 위치 지도")
    }

    @ViewBuilder private var placeFacts: some View {
        Label("350m", systemImage: "location")
        Label("도보 약 5분", systemImage: "figure.walk")
        Label("ERICA 인근", systemImage: "mappin")
    }

    private func reason(_ symbol: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.indigo).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

}
#endif
