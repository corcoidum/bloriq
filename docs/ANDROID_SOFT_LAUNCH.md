# Android 소프트 론칭 체크리스트

광고 없는 비공개 테스트 후보를 목표로 한다. 제출 전 항목의 검증 결과를 기록한다.

## 확인된 환경과 제한

- 로컬 Flutter 3.47.8 / Dart 3.13.7 실행 가능. doctor는 SDK checkout을 `user-branch`로 표시하고 Flutter/Dart PATH 미등록을 보고한다. 재현용 버전을 유지하며 출시 전 공식 배포 SDK와 호환성을 확인한다.
- Flutter Gradle 확장의 compile/target SDK 기본값은 36이다. 앱은 이 값을 참조한다. APK manifest를 빌드해 확인한 결과는 아직 없다.
- 실제 출시용 키로 서명한 AAB와 기기 설치는 제출 전에 확인한다.

## 출시용 업로드 키 설정

`android/key.properties`가 있으면 Gradle이 그 키로 릴리스에 서명한다. 이 파일이 없으면 로컬 테스트용 debug 서명을 쓴다. 파일을 만들었다면 네 항목과 키 경로를 모두 채워야 한다.

1. 소유자가 저장소 밖에서 업로드 키를 생성한다. 비밀번호는 명령줄 인자로 넣지 말고 프롬프트에서 입력한다. [Flutter Android 서명 가이드](https://docs.flutter.dev/deployment/android#sign-the-app)

   ```bash
   keytool -genkeypair -v -storetype JKS -keystore "$HOME/bloriq-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. 로컬 `android/key.properties`에 다음 항목을 채운다. `storeFile`은 절대 경로 또는 `android/` 기준 상대 경로다.

   ```properties
   storeFile=/Users/yourname/bloriq-upload.jks
   storePassword=저장소_비밀번호
   keyAlias=upload
   keyPassword=키_비밀번호
   ```

3. 키는 저장소 밖의 암호화된 저장소에도 백업하고 비밀번호는 비밀번호 관리자에 보관한다. 키 파일과 설정의 읽기 권한을 소유자로 제한하고, `git check-ignore android/key.properties`로 Git 제외 여부를 확인한다.
4. 제출 후보를 빌드하기 전에 `cd android && ./gradlew :app:signingReport`에서 `release` 변형의 설정이 `release`인지 확인한다. 프로젝트 루트에서 `flutter build appbundle --release`를 실행하고 생성된 AAB의 서명을 확인한다.

## 출시 구현 범위

- P2 힌트 UX, 실제 광고 SDK와 동의 관리는 별도 작업으로 다룬다.
- 광고 없이 진행 가능해야 한다. Banner와 IAP는 추가하지 않는다. 향후 Rewarded Hint는 명시적 선택·취소/실패 시 보드 유지가 필수다.
- Interstitial 실험은 튜토리얼과 1~10레벨에서 제외하고, 이후에도 약 5레벨 완료 뒤 자연스러운 결과 화면으로 한정해 별도로 승인받는다.

## 제출 전 확인

- [ ] Android SDK·호환 JDK·라이선스·실기기를 준비하고 `flutter doctor -v`, `flutter devices` 기록
- [ ] debug APK 설치, 비행기 모드 시작/플레이/기록 복원, 앱 종료·복귀, 오디오, 큰 글꼴, 모션 줄이기 확인
- [ ] `flutter run --profile -d <deviceId>`에서 UI/raster frame 측정. 60Hz의 16.7ms 예산 초과 프레임과 기기 조건 기록
- [ ] 새 앱/업데이트의 [API 36 이상 요건](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en)을 실제 산출물에서 확인
- [ ] Flutter 엔진·모든 네이티브 플러그인의 [16KB 페이지 지원](https://developer.android.com/guide/practices/page-sizes)을 최종 APK/AAB와 호환 기기에서 확인
- [ ] 소유자가 업로드 키와 Play App Signing 방식을 확정하고, 서명 설정과 키를 Git에서 제외했는지 확인
- [ ] 출시용 서명 설정으로 AAB를 빌드하고 서명과 기기 설치를 검증
- [ ] 실제 게임과 일치하는 한국어/영어 스토어 설명·아이콘·Android 화면 준비. 위젯 캡처를 실기기 증거로 표시하지 않음
- [ ] 개인정보 처리방침·Data Safety를 실제 빌드의 데이터 흐름과 SDK 기준으로 검토. 선택형 수동 내보내기도 검토에 포함
- [ ] 2023-11-13 이후 생성된 개인 계정에 해당하면 [12명 연속 14일 비공개 테스트](https://support.google.com/googleplay/android-developer/answer/14151465?hl=en) 등 계정별 생산 액세스 요건 확인
- [ ] Play Console Pre-launch report와 실제 테스트 버전의 오류 확인. 외부 crash 수집이 없는 현재 로컬 이벤트만으로 Crash-free users를 계산하지 않음
- [ ] 5명 관찰과 후보 26~40의 수동 검토 완료. 공개 목록 편입 전 레벨 감사와 양쪽 solver 재실행
- [ ] 스토어 업로드·공개·국가별 배포는 별도 승인 후 진행

필수 항목이 남으면 코드/웹 검증 통과와 관계없이 소프트 론칭 완료로 보고하지 않는다.
