# Android 소프트 론칭 체크리스트

기준일: 2026-10-29. **현재 소프트 론칭 준비 완료가 아니다.** 광고 없는 비공개 테스트 후보를 목표로 한다.

## 확인된 환경과 제한

- 로컬 Flutter 3.47.8 / Dart 3.13.7 실행 가능. doctor는 SDK checkout을 `user-branch`로 표시하고 Flutter/Dart PATH 미등록을 보고한다. 재현용 버전을 유지하며 출시 전 공식 배포 SDK와 호환성을 확인한다.
- Flutter Gradle 확장의 compile/target SDK 기본값은 36이다. 앱은 이 값을 참조한다. APK manifest를 빌드해 확인한 결과는 아직 없다.
- `flutter build apk --debug --no-pub` 실행 결과: `No Android SDK found`. SDK·JDK·라이선스·기기 연결을 준비해야 한다.
- 기존 `release.signingConfig`는 debug 키다. AAB·실제 출시용 서명을 검증하지 않았다. 자동으로 키를 생성하거나 기존 사용자 키를 복사하지 않는다.

## 구현 승인 전 경계

- P2 힌트 UX, 실제 광고 SDK, 동의 관리, release 서명 변경은 별도 승인 전 구현하지 않는다.
- 광고 없이 진행 가능해야 한다. Banner와 IAP는 추가하지 않는다. 향후 Rewarded Hint는 명시적 선택·취소/실패 시 보드 유지가 필수다.
- Interstitial 실험은 튜토리얼과 1~10레벨에서 제외하고, 이후에도 약 5레벨 완료 뒤 자연스러운 결과 화면으로 한정해 별도로 승인받는다.

## 제출 전 확인

- [ ] Android SDK·호환 JDK·라이선스·실기기를 준비하고 `flutter doctor -v`, `flutter devices` 기록
- [ ] debug APK 설치, 비행기 모드 시작/플레이/기록 복원, 앱 종료·복귀, 오디오, 큰 글꼴, 모션 줄이기 확인
- [ ] `flutter run --profile -d <deviceId>`에서 UI/raster frame 측정. 60Hz의 16.7ms 예산 초과 프레임과 기기 조건 기록
- [ ] 새 앱/업데이트의 [API 36 이상 요건](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)을 실제 산출물에서 확인
- [ ] Flutter 엔진·모든 네이티브 플러그인의 [16KB 페이지 지원](https://developer.android.com/guide/practices/page-sizes)을 최종 APK/AAB와 호환 기기에서 확인
- [ ] 소유자가 upload key와 Play App Signing 방식을 확정. 누락 시 release가 debug 키로 조용히 빌드되지 않도록 설정 변경
- [ ] 키·비밀번호는 환경/로컬 key.properties로 관리하고 Git 미포함 확인. release 설정 변경 승인 후에만 서명된 AAB 빌드·설치 검증
- [ ] 실제 게임과 일치하는 한국어/영어 스토어 설명·아이콘·Android 화면 준비. 위젯 캡처를 실기기 증거로 표시하지 않음
- [ ] 개인정보 처리방침·Data Safety를 실제 빌드의 데이터 흐름과 SDK 기준으로 검토. 선택형 수동 내보내기도 검토에 포함
- [ ] 2023-11-13 이후 생성된 개인 계정에 해당하면 [12명 연속 14일 비공개 테스트](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) 등 계정별 생산 액세스 요건 확인
- [ ] Play Console Pre-launch report와 실제 테스트 버전의 오류 확인. 외부 crash 수집이 없는 현재 로컬 이벤트만으로 Crash-free users를 계산하지 않음
- [ ] 5명 관찰과 후보 26~40의 수동 검토 완료. 공개 목록 편입 전 레벨 감사와 양쪽 solver 재실행
- [ ] 스토어 업로드·공개·국가별 배포는 별도 승인 후 진행

필수 항목이 남으면 코드/웹 검증 통과와 관계없이 소프트 론칭 완료로 보고하지 않는다.
