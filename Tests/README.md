# super-parakeet PDF·광고 수정 검증

검증 기준: 최초 HEAD `c458334`, 최초 작업 트리 clean. 원본 저장소 `/Volumes/projects/XcodeProjects/super-parakeet`에 승인된 수정만 반영했다. 커밋·push·버전 변경·서명·배포는 하지 않았다. `Podfile`과 `Podfile.lock`은 변경하지 않았다. 출결 앱과 서버 저장소, 사용자 PDF/앱 데이터/설정/권한은 사용하거나 변경하지 않았다.

## PDF 변경

- `Model/PrintJobs.swift:147`: App Group 파일 manifest를 권위 있는 큐로 사용한다. stable flock 파일로 프로세스 간 읽기-수정-쓰기를 직렬화하고, UUID 디렉터리에 PDF를 먼저 게시한 뒤 manifest를 원자적으로 교체한다. UserDefaults는 최초 이전에만 읽으며 원본 백업은 보존한다. 목록 reload는 쓰지 않는다.
- `Model/PrintJobs.swift:242,385`: 임시 provider URL은 callback 안에서 동기 복사한다. security scope와 coordinated read, PDFKit 검증을 적용했다. file representation 실패 시 Data representation을 시도하고 파일 URL attachment도 처리한다. 파일명이 같아도 별도 문서가 된다.
- `Model/PrintJobs.swift:427` 및 share extension: 모든 input item/attachment를 처리한다. 진행 중 Close를 막으며 실패한 항목만 재시도한다. 취소는 게시 중인 항목 완료를 기다리고 이미 성공한 항목을 보존하며 늦은 callback을 무시한다.
- `Service/Requests.swift:273`, `ViewModel/UploadStatusViewModel.swift`: 성공 응답이 확인된 UUID와 수량만 차감한다. 부분 실패/취소 때도 성공한 동시 작업 응답을 drain하며 새 공유 문서는 남긴다. 여러 scene의 중복 업로드를 막고 취소 drain 전 재시작을 차단한다.
- `View/MainView.swift`: cold launch/foreground/로그인 변경 및 active 동안 새 manifest를 reload한다. UI에 파일명과 저장 오류를 표시한다.

## 광고 변경

- `Service/AdLifecycle.swift`: single-flight load, 실행/요청 토큰, 캐시 만료, 로드 timeout, presentation gate, 한 번만 종료되는 상태를 도입했다. 보상 callback과 dismissal을 분리한다. 실패 뒤 늦은 보상은 무시한다.
- 4개 광고 manager 및 `RewardedAdFlowCoordinator.swift`: 실제 표시 직전 현재 scene의 presenter를 다시 찾고 canPresent를 검증한다. AppOpen과 연속 광고가 겹치지 않게 한다. no-fill/실패/취소/배경 전환/중복 callback에서 일관되게 종료한다.
- watchdog는 SDK UI가 남아 있으면 다음 광고를 겹쳐 표시하거나 강제로 닫지 않는다. 원래 scene의 modal/transition/새 window를 확인하고 UI가 사라졌을 때만 복구한다.
- `MainView.swift:249,332`: 버튼을 누른 MainView의 window에 속한 controller를 사용한다. 다음 단계마다 동의/취소를 제공하고 dialog 바깥 dismissal도 취소한다. 실행별 보상을 별도로 보관하고 일반 interstitial의 종료를 보상 지급 조건으로 삼지 않는다.
- 독립 리뷰에서 발견한 callback 교체, 실패 후 보상, no-fill 알림 누락, 다중 창 presenter 문제를 보완했다. 최신 통합본에 추가 P1/P2 발견 없음.

## 실행한 검증

| 검증 | 결과 |
|---|---|
| PDF 회귀 | 47 checks, 0 failures |
| 광고 상태 회귀 | 20 scenarios passed |
| 실제 잠금 버전 SDK 포함 Debug simulator app+extension 빌드 | BUILD SUCCEEDED |
| 실제 SDK 포함 Release generic iOS app+extension, signing off | BUILD SUCCEEDED |
| git diff --check | 통과 |
| 합성 PDF ShareView UI | 1개 성공·1개 실패, 재시도/Close 표시 시각 확인 |

PDF 회귀는 운영 네트워크 클라이언트를 전송할 수 없는 stub으로 바꾸어 production 큐/provider/session/planner/use-case/VM을 컴파일한다. 임시 폴더와 합성 PDF, 메모리 defaults만 쓴다. 4개 프로세스의 동일 파일명 60개 공유, callback 임시 URL/Data, cold/warm reload, 이전 데이터 보존, 손상된 manifest 방어, partial retry, cancel/late callback, 업로드 중 새 공유·부분 성공·취소 drain 등을 검증했다. 이전 코드의 동시 snapshot 덮어쓰기는 테스트에서 실패했고 수정본은 통과했다.

광고 회귀는 SDK/네트워크 없이 fake load/present와 clock으로 상태를 확인한다. 3단계 순서, 재시도, 중복 callback, no-fill, timeout, 만료, late reward, UI 가시성, AppOpen 충돌을 확인했다. 실제 SDK API 호환성은 Google Mobile Ads 12.14.0, Alamofire 5.11.0, UMP 3.1.0을 `pod install --deployment`한 별도 `/tmp` 복사본에서 전체 빌드했다. 원본에는 Pods를 설치하지 않았다.

합성 UI 전용 앱은 별도 simulator device set에서 실행했다. 운영 앱과 광고 SDK는 포함하지 않았다. 생성한 simulator만 종료/삭제했다. 이 화면은 사용자가 첨부한 JPEG와 다르다.

## 재실행

macOS/Xcode 환경에서 저장소 루트:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Tests/run_pdf_regression.py
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer sh Tests/run_ad_regression.sh
```

도구 sandbox가 NSItemProvider의 합성 파일 읽기까지 막으면 PDF suite는 별도 파일 접근 허용 환경에서 실행해야 한다. 실제 사용자 PDF를 fixture로 사용하지 않는다.

## 남은 범위와 출시 전 판단

1. 실제 Files/Safari/다른 공급자 앱의 공유 sheet, 실제 기기에서 extension 강제 종료/메모리 압박, mediation SDK의 실제 Close 및 다중 창 UI는 아직 확인하지 않았다. 기기에서 test ad ID와 합성 PDF만 사용하여 확인해야 한다. 실제 광고를 호출하거나 실제 인쇄/업로드하지 않았다.
2. 사용자가 제공한 JPEG는 지원되는 Library 다운로드 경로에서 403으로 실패했다. 재발급 1회 후 중단했으며 픽셀을 보지 못했다. 따라서 그 이미지의 Close 위치/광고 종류는 판정하지 않았다.
3. 기존 기프티콘 지급 약속 및 '보상 지급' 문구를 유지했다. 이 앱에는 영속적 보상 원장/서버 검증을 새로 구현하지 않았다. AdMob은 gift card 등 직접 금전 보상을 금지하고 간접 보상에도 앱 내 사용·양도 불가 조건을 둔다. 기존 약속의 정책 적합성과 실제 지급 설계는 출시 전 수정 또는 재설계가 필요하다. 이번 상태/Close 수정만으로 정책 적합성을 확정할 수 없다.
4. 응답이 유실된 서버 수락의 exactly-once 업로드는 서버 idempotency 지원 없이는 보장하지 못한다. 확인된 성공만 로컬 큐에 반영한다. 강제 종료 시 미게시 staging 파일은 남을 수 있으며 안전한 age-based cleanup은 별도 개선이다. 파일 atomic replacement는 hard power loss까지 fsync 내구성을 보증하지 않는다.

## 공식 문서

- [Apple loadFileRepresentation](https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:)): completion이 반환된 뒤 임시 파일 제거 가능.
- [Google rewarded ads](https://developers.google.com/admob/ios/rewarded): 캐시 만료 및 mediation 보상/dismiss 순서.
- [Google rewarded interstitial](https://developers.google.com/admob/ios/rewarded-interstitial): introductory screen과 opt-out.
- [Google rewards policy](https://support.google.com/admob/answer/7313578?hl=en-GB): 보상 유형·사전 설명·자발적 동의·약속 보상 지급.

검증 로그·합성 화면·최초 원인 보고서는 Codex 작업 디렉터리 `/Users/kyoungsukim/Documents/Codex/2026-10-09/task-2`에 보관했다.
