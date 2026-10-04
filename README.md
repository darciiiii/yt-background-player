# BG Tube — 백그라운드 YouTube 플레이어 (iPhone)

홈 화면으로 나가거나 화면을 잠가도 YouTube 재생이 끊기지 않는 개인용 iPhone 앱입니다.
SwiftUI + WKWebView로 m.youtube.com을 그대로 띄우므로 검색·구독·재생목록·로그인을 모두 그대로 쓸 수 있습니다.

## 기능

- 백그라운드 / 잠금 화면 재생 유지 (`UIBackgroundModes: audio` + `AVAudioSession .playback`)
- 페이지가 항상 "보이는 상태"라고 인식하도록 Visibility API를 가로채서 YouTube가 스스로 멈추지 않게 함
- 백그라운드 진입 시 WebKit이 영상을 멈추면 자동으로 다시 재생
- 잠금 화면·제어 센터·이어폰 버튼: 재생/일시정지, 다음/이전, 탐색 바
- 잠금 화면에 제목·채널·썸네일 표시
- 전화·Siri 등 오디오 중단 후 자동 재개
- 하단 바: 뒤로/앞으로/홈/새로고침/재생·일시정지
- `youtube://` 같은 "앱에서 열기" 링크 차단 (YouTube 앱으로 튕기지 않음)

## 설치 방법 (Mac 필요)

1. Mac에 Xcode 16 이상 설치
2. 이 저장소를 받아 `YTBackgroundPlayer.xcodeproj` 열기
3. 왼쪽에서 프로젝트 → `YTBackgroundPlayer` 타깃 → **Signing & Capabilities**
   - **Team**: 본인 Apple ID 선택 (Xcode → Settings → Accounts에서 추가)
   - **Bundle Identifier**: `com.example.ytbgplayer`를 고유한 값으로 변경 (예: `com.본인아이디.bgtube`)
4. 아이폰을 USB로 연결 → 상단에서 기기 선택 → ▶ 실행
5. 아이폰에서 **설정 → 일반 → VPN 및 기기 관리**에서 개발자 앱 신뢰
6. iOS 16 이상은 **설정 → 개인정보 보호 및 보안 → 개발자 모드** 켜기

> 무료 Apple ID로 설치하면 7일마다 Xcode에서 다시 실행해 서명을 갱신해야 합니다.
> 유료 개발자 계정(연 $99)은 1년간 유지됩니다.

## 사용 팁

- 영상을 한 번 재생한 뒤 홈으로 나가거나 화면을 잠그면 그대로 계속 재생됩니다.
- 만약 멈췄다면 잠금 화면/제어 센터의 ▶ 버튼을 누르면 이어서 재생됩니다.
- YouTube 로그인은 앱 안에서 한 번만 하면 유지됩니다.

## 구조

| 파일 | 역할 |
|---|---|
| `YTBackgroundPlayer/YTBackgroundPlayerApp.swift` | 앱 진입점 |
| `YTBackgroundPlayer/ContentView.swift` | 웹뷰 + 하단 컨트롤 바 |
| `YTBackgroundPlayer/PlayerController.swift` | WKWebView 설정, 오디오 세션, 잠금 화면 컨트롤, 백그라운드 재개 |
| `YTBackgroundPlayer/BackgroundScript.swift` | 페이지에 주입하는 JS (Visibility 우회, 재생 제어, 상태 보고) |
| `Config/Info.plist` | 백그라운드 오디오 모드 |
