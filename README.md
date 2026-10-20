# XRCH Companion

ARCH 위치 기반 AR 앱을 위한 iPhone 동반 앱 프로토타입입니다. iPhone의 위치와 나침반 방향을 Quest 앱으로 보내고, 가상 GPS와 진단 화면으로 연동을 확인할 수 있습니다.

## 기능

- 실제 GPS 또는 지도에서 선택한 가상 GPS 좌표 전송
- 가상 GPS 연속 전송: 실행 중 1초마다 위치 패킷 전송
- Quest와 Bluetooth LE 자동 검색 및 연결
- 위치와 헤딩 데이터를 UDP 또는 BLE로 전달
- AI 추천 장소를 Quest에 보라색 POI로 표시
- 현재 헤딩으로 Quest 방향 보정, 실시간 헤딩 보정 모드
- AI 추천 탭: 익명 또는 로그인 사용자의 토큰과 실제 iPhone GPS로 Supabase `chat` 함수에 질문을 보내고 GPU 추천 답변과 장소를 대화로 표시
- 기타 탭: Supabase Auth 로그인·회원가입·로그아웃, `chat/plan` 인증 연결 확인, 마지막 추천 요청 상태·응답 모델·GPU 사용 여부·GPS 정확도 확인
- 개발자 진단: 연결/권한/네트워크 상태, 좌표, 정확도, 최근 패킷, 이벤트 로그

탐색·지도 화면의 장소는 AI 추천 응답으로 갱신됩니다. 저장·프로필은 현재 로컬 UI 프로토타입입니다. AI 추천은 로그인 없이 익명 인증 세션으로 사용할 수 있습니다. 위치 권한과 네트워크 연결이 필요하며, Supabase/GPU 워커 상태에 따라 응답이 실패할 수 있습니다. 익명·로그인 세션의 access/refresh token은 iPhone Keychain에 저장되고 Supabase Auth API로 갱신됩니다. 익명 사용자는 서버 기준 하루 5회(한국 시간 자정 초기화)의 GPU 예산을 사용하며 AI 추천 탭에 남은 횟수를 표시합니다. 일반 계정에서 로그아웃하면 기존 게스트 세션을 복원하므로 로그인 전의 사용량이 유지됩니다. 서버의 `usage` 함수와 GPU quota migration 배포가 필요합니다.

## 요구 사항

- Xcode 26.3 이상 권장
- iOS 17 이상
- iPhone 실기기: 실제 위치, 나침반, BLE 연동 테스트에 필요
- Quest 측 Unity 앱: `arch.location.v1` 위치 패킷과 아래 UDP/BLE 연결 규약을 지원해야 합니다.

## 실행

1. `XRCH.xcodeproj`를 Xcode에서 엽니다.
2. `XRCH` scheme을 선택하고 iOS Simulator 또는 iPhone을 대상으로 실행합니다.
3. iPhone 실기기에서 실행할 때는 Signing & Capabilities에서 본인 Apple 개발 팀을 선택합니다.
4. **기타 → 계정**에서 로그인하거나 회원가입합니다. **AI 추천** 탭에서 질문을 입력하면 현재 GPS와 로그인 토큰으로 Supabase `chat` 함수를 호출합니다. 답변에 포함된 장소 카드를 누르면 상세 정보가 열리고 탐색·지도 탭에도 같은 결과가 표시됩니다.
5. 앱에서 **기기 → Quest 검색 및 연결**을 눌러 BLE 연결을 시작합니다.
6. **GPS 모드**에서 실제 GPS 또는 가상 GPS를 고릅니다. 가상 모드에서는 지도를 이동하고 **이 위치를 가상 GPS로 적용**을 누릅니다.
7. **헤딩 보정** 탭에서 **실시간 보정 시작**을 누르면 iPhone 나침반 방향 변경을 Quest로 보냅니다. 한 번만 보정하려면 기기 화면의 **현재 방향으로 Quest 보정**을 사용합니다.
8. **기기 → 개발자 진단**에서 전송 횟수, 최근 패킷, 센서 값과 이벤트 로그를 확인합니다.

가상 GPS의 기본 좌표는 한양대학교 ERICA 인근입니다. 가상 GPS는 연속 전송을 시작한 뒤에도 적용한 좌표를 1초마다 다시 보냅니다. 지도 좌표를 바꾸면 실행 중인 연결에 새 좌표를 즉시 한 번 보내고 이후 1초 주기를 이어갑니다.

시뮬레이터는 화면과 가상 GPS 전송 흐름을 확인하는 용도로 사용할 수 있습니다. 실제 나침반과 BLE 기기 연결 동작은 iPhone과 Quest 실기기에서 확인하세요.

## 연결 방식

### Bluetooth LE

앱은 아래 서비스를 광고하는 Quest를 검색하고, 위치 characteristic에 JSON 바이트를 씁니다.

| 항목 | UUID |
|---|---|
| Service | `A6C40001-7D2A-4B2E-9E31-8A6F310A1201` |
| Location characteristic | `A6C40002-7D2A-4B2E-9E31-8A6F310A1201` |

BLE 패킷은 줄바꿈(`\n`)으로 끝납니다. characteristic 최대 쓰기 길이에 따라 여러 조각으로 나뉠 수 있으므로 Quest 수신부는 조각을 모아 줄바꿈 단위로 JSON을 복원해야 합니다.

### UDP

UDP 포트는 `47777`입니다. Quest 수신 IP를 입력해 전송을 시작하며, iPhone과 Quest가 서로 도달 가능한 네트워크에 있어야 합니다. iOS 앱에서 로컬 네트워크 권한 요청을 허용하세요.

```text
iPhone ── UDP :47777 ──▶ Quest Unity receiver
       └─ Bluetooth LE ─▶ Quest Unity receiver
```

현재 기본 기기 화면은 BLE 연결 흐름을 제공합니다. UDP sender는 `QuestLocationBridge`에 구현되어 있으며, 사용 시 수신 호스트 주소를 전달해야 합니다.

## 위치 패킷

UDP는 JSON 객체 하나를 datagram으로 보내며, BLE는 같은 JSON 뒤에 줄바꿈을 붙입니다. 일반 위치 패킷 예시:

```json
{
  "type": "arch.location.v1",
  "source": "virtual",
  "sequence": 12,
  "timestamp": 1790000000.0,
  "latitude": 37.3017362,
  "longitude": 126.8385608,
  "altitude": 0,
  "horizontalAccuracy": 1
}
```

헤딩 보정 패킷에는 다음 필드가 추가됩니다.

```json
{
  "trueHeading": 135.0,
  "headingAccuracy": 4.0,
  "headingCalibration": true,
  "headingSource": "iphone_compass_live"
}
```

`headingSource`는 UDP 실시간 보정에서 `iphone_compass_live`, BLE 보정에서 `iphone_compass`입니다. 일반 위치 패킷에는 헤딩 보정 필드가 포함되지 않을 수 있습니다. `timestamp`는 Unix 초 단위이고 `sequence`는 전송마다 증가합니다.

## AI 추천 위치 패킷

기기 연결 화면에서 **AI 추천 위치를 Quest에 표시**를 누르면 현재 AI 추천 결과를
같은 UDP/BLE 채널로 전송합니다. Unity는 기존 디버그 추천 표시를 끄고, 아래 패킷의
장소를 보라색 추천 POI로 표시합니다. 좌표가 정상인 장소는 Unity의 일반 POI 표시
거리 밖이어도 새 billboard로 생성됩니다.

```json
{
  "type": "arch.ai_recommendations.v1",
  "source": "xcode",
  "sequence": 42,
  "timestamp": 1790000000.0,
  "clearDebugRecommendations": true,
  "recommendations": [
    {
      "poiId": "place-123",
      "name": "Example Cafe",
      "category": "카페",
      "address": "주소",
      "description": "추천 장소",
      "latitude": 37.3017,
      "longitude": 126.8386,
      "distanceMeters": 420,
      "score": 0.96,
      "reason": "조용히 작업하기 좋은 장소"
    }
  ]
}
```

BLE에서는 기존 위치 패킷과 동일하게 JSON 뒤에 줄바꿈을 붙이고 characteristic
최대 길이에 맞춰 분할합니다. Unity는 `arch.ai_recommendation.v1` 별칭도 허용합니다.

## 권한과 개인정보

앱은 iPhone 위치를 앱 사용 중에 읽고, Bluetooth로 Quest를 검색·연결하며, UDP 사용 시 로컬 네트워크에 접근합니다. AI 추천 질문과 현재 위치는 Supabase Edge Function으로 전송되고 서버의 GPU 추천 작업에 사용됩니다. Quest 위치/헤딩 패킷을 중계하는 외부 서버는 없습니다.

## Supabase 게스트 인증

앱 시작 시 Supabase Auth의 `/auth/v1/signup`에 빈 JSON을 보내 익명 세션을 생성합니다. 기존 세션이 있으면 Keychain에서 복원하고, 만료 전 `/auth/v1/token?grant_type=refresh_token`으로 갱신합니다. 동시에 발생한 인증 요청은 한 작업을 공유합니다. 네트워크 장애 때 기존 세션을 삭제하거나 새 게스트 계정을 생성하지 않습니다.

`XRCH/SupabaseConfiguration.swift`에는 프로젝트 URL과 서버 웹 클라이언트에 공개된 legacy anon 키만 있습니다. 이 키는 공개 클라이언트 설정이며 사용자 권한을 대신하지 않습니다. service-role 키나 GPU 서버 비밀값을 앱에 넣지 않습니다. 기존 ARCH_CLIENT_SECRET은 추천 요청에 사용하지 않습니다.

추천과 연결 확인 요청은 `Authorization: Bearer <사용자 JWT>` 및 프로젝트 `apikey` 헤더를 보냅니다. 게스트에게 로그인 폼 입력을 요구하지 않습니다. 계정 화면은 게스트와 정식 로그인을 구분하고, 기존 이메일 로그인은 선택적으로 유지합니다. Apple 로그인은 후속 구현입니다.

실제 연결에는 서버 관리자가 Supabase 익명 인증을 활성화하고, JWT 지원 및 게스트 GPU 한도 PR을 배포해야 합니다. 서버 PR이 배포되기 전에는 인증 비활성화 오류 또는 API_KEY_REQUIRED가 발생할 수 있습니다. config.toml 변경만으로 운영 설정이 바뀌지 않습니다.

GPU 일일 한도 응답(429)은 초기화 시각과 함께 표시합니다. 정식 계정 로그아웃은 Supabase의 해당 세션을 종료한 뒤 기존 게스트 세션을 복원합니다. 계정 연결·삭제, App Attest 및 폐기된 세션의 복구 UX는 후속 작업입니다. 기본 탐색 화면의 기존 데이터 소스는 이 변경에서 수정하지 않습니다.

## 프로젝트 구성

- `XRCH/MyApp.swift`: 앱 진입점
- `XRCH/CompanionAppViews.swift`: 탐색, 지도, 기기, 헤딩 보정 화면
- `XRCH/ContentView.swift`: 개발자 진단 패널
- `XRCH/QuestLocationBridge.swift`: Core Location, Core Bluetooth, UDP, 패킷 직렬화

## 익명 인증 검증

실제 Supabase와 Keychain을 변경하지 않는 모의 인증 검증:

```sh
xcrun swiftc -swift-version 5 -parse-as-library XRCH/SupabaseConfiguration.swift XRCH/CompanionUsage.swift XRCH/AppleSignInNonce.swift XRCH/CompanionAuthSession.swift Tests/AuthSessionHarness.swift -o /tmp/xrch-auth-tests
/tmp/xrch-auth-tests
```

네트워크 또는 Keychain 읽기 실패 시 저장된 익명 계정을 버리지 않습니다. 서버가 access token을 401로 거절하면 한 번 갱신 후 재요청하고, 429·서버 오류·타임아웃은 자동 재시도하지 않습니다. 실패 환급·추천 요청 재전송 멱등성은 서버 후속 작업입니다.

## 구형 서버의 게스트 인증 호환

앱은 게스트 Auth 사용자 JWT와 공개 프로젝트 apikey로 먼저 요청합니다. 서버가 정확히 HTTP 401 / API_KEY_REQUIRED를 반환할 때만 같은 JWT로 REST profiles에서 현재 사용자 id의 api_key를 조회하고, 해당 사용자에게 서버가 발급한 키를 x-api-key 헤더에 넣어 원래 요청을 한 번 재시도합니다. 새로운 사용자나 공유 키를 만들지 않고, 키는 로그나 UserDefaults에 기록하지 않습니다. JWT만 받는 새 서버에는 추가 조회가 없습니다.

이 호환 경로는 운영 DB에 handle_new_user_profile 트리거 및 authenticated 사용자의 본인 프로필 SELECT 정책이 적용돼 있어야 합니다. 키가 없거나 조회가 거절되면 서버 설정 문제를 표시하며 인증을 우회하지 않습니다. 검색·chat/plan·chat에 동일하게 적용됩니다. 서버 배포는 이 변경에 포함되지 않습니다.

## 다른 장소 보기

채팅의 최근 추천 아래에서 다른 장소 보기를 누르면 원래 질문을 chat/plan으로 분석하고 search(provider=kakao-local)로 현재 GPS/설정 반경의 후보를 받습니다. 이미 보여 준 추천 장소를 제외한 후보를 chat.places로 보내 AI 추천을 요청합니다. 일반 추천과 동일한 chat 서버 사용량 한도를 공유하며, 게스트는 클릭 시 usage를 새로 확인합니다. 한도 확인 실패 또는 잔여 0회면 추가 추천을 진행하지 않습니다. 검색 후보가 없으면 GPU 추천을 요청하지 않습니다. 운영 서버의 usage 및 chat quota 기능이 있어야 서버 기준 하루 5회가 보장됩니다.
