#if DEBUG
import SwiftUI

struct DeviceDiagnosticsView: View {
    @ObservedObject var bridge: QuestLocationBridge

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    connectionHero
                    bleCard
                    locationCard
                    diagnosticsCard
                    packetCard
                    eventLogCard
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("XRCH Companion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("로그 지우기") { bridge.clearEvents() }.font(.caption)
                }
            }
        }
        .tint(.indigo)
    }

    private var connectionHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(bridge.connectionColor.opacity(0.16)).frame(width: 48, height: 48)
                    Image(systemName: bridge.connectionSymbol)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(bridge.connectionColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("QUEST LOCATION BRIDGE").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Text(bridge.connectionStateText).font(.title3.weight(.semibold))
                    Text(bridge.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Circle().fill(bridge.connectionColor).frame(width: 10, height: 10)
                    .shadow(color: bridge.connectionColor.opacity(0.55), radius: 5)
            }
            HStack(spacing: 10) {
                MetricPill(title: "전송", value: "\(bridge.sentCount)", systemImage: "paperplane.fill")
                MetricPill(title: "마지막", value: bridge.lastSentAgoText, systemImage: "clock.fill")
                MetricPill(title: "패킷", value: bridge.lastPacketSizeText, systemImage: "shippingbox.fill")
            }
        }
        .debugCard()
    }

    private var bleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("Quest BLE", systemImage: "antenna.radiowaves.left.and.right")
            InfoRow(label: "기기", value: bridge.bleDeviceText)
            InfoRow(label: "신호", value: bridge.bleRSSIText)
            InfoRow(label: "서비스", value: "ARCH Location")
            HStack(spacing: 10) {
                Button {
                    bridge.isRunning ? bridge.stop() : bridge.startBLE()
                } label: {
                    Label(bridge.isRunning ? "BLE 중지" : "Quest 검색 및 연결",
                          systemImage: bridge.isRunning ? "stop.fill" : "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button { bridge.sendCurrentOrTestLocationBLE() } label: {
                    Label("1회 전송", systemImage: "paperplane")
                }
                .buttonStyle(.bordered)
                Button { bridge.calibrateQuestHeading() } label: {
                    Label("초기 방향 보정", systemImage: "location.north.line.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!bridge.isRunning)
            }
        }
        .debugCard()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardTitle("iPhone 위치", systemImage: "location.circle.fill")
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bridge.latitudeText).monospacedDigit()
                    Text(bridge.longitudeText).monospacedDigit()
                }
                .font(.title3.weight(.medium))
                Spacer()
                Text(bridge.locationSourceText)
                    .font(.caption.weight(.semibold)).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.indigo.opacity(0.12), in: Capsule()).foregroundStyle(.indigo)
            }
            Divider()
            InfoRow(label: "수평 정확도", value: bridge.accuracyText)
            InfoRow(label: "현재 방향", value: bridge.headingText)
            InfoRow(label: "방향 정확도", value: bridge.headingAccuracyText)
            InfoRow(label: "고도", value: bridge.altitudeText)
            InfoRow(label: "위치 시각", value: bridge.locationTimestampText)
            InfoRow(label: "위치 나이", value: bridge.locationAgeText)
        }
        .debugCard()
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("진단", systemImage: "stethoscope")
            InfoRow(label: "무선 상태", value: bridge.networkPathText)
            InfoRow(label: "위치 권한", value: bridge.authorizationText)
            InfoRow(label: "BLE 상태", value: bridge.connectionStateText)
            InfoRow(label: "Endpoint", value: bridge.endpointText)
            InfoRow(label: "메시지 계약", value: "arch.location.v1")
            InfoRow(label: "앱 버전", value: bridge.appVersionText)
            InfoRow(label: "기기", value: bridge.deviceText)
        }
        .debugCard()
    }

    private var packetCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("최근 송신 패킷", systemImage: "curlybraces")
            ScrollView(.horizontal, showsIndicators: false) {
                Text(bridge.lastPacketText).font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
        .debugCard()
    }

    private var eventLogCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardTitle("이벤트 로그", systemImage: "list.bullet.rectangle")
            if bridge.events.isEmpty {
                Text("아직 이벤트가 없습니다.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(Array(bridge.events.enumerated()), id: \.offset) { index, event in
                    Text(event).font(.system(size: 11, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if index < bridge.events.count - 1 { Divider() }
                }
            }
        }
        .debugCard()
    }
}

private struct CardTitle: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View { Label(title, systemImage: systemImage).font(.headline) }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

private struct MetricPill: View {
    let title: String
    let value: String
    let systemImage: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(title, systemImage: systemImage).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

private extension View {
    func debugCard() -> some View {
        padding(16)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
    }
}

#Preview { DeviceDiagnosticsView(bridge: QuestLocationBridge()) }
#endif
