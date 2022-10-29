# super-parakeet (iOS 애플리케이션)
캠퍼스 프린터기를 사용할 때 드라이버가 윈도우밖에 없어서 아이패드를 주로 쓰는 사람들은 꼭 윈도우 노트북을 켜야 하더라구요. 그게 너무 불편해서 하나 만들었습니다. 짜잔. 

![image](https://user-images.githubusercontent.com/61102713/198850376-cd9291b6-df8a-4084-bc3a-d030c2df57b3.png)

캠퍼스에서 프린트 하나 한다고 윈도우 노트북 켜서 메일 보내고 파일 받아서 프린트하지 마세요. 번거롭잖아요. 이제 모바일에서도 프린트 하자구요.
모바일에서 pdf 파일을 열고 공유 버튼을 눌러 이 프린터 앱으로 파일을 공유하세요. 앱으로 돌아와서 휴대폰 번호를 입력하고 문서를 확인한 뒤 print 버튼을 누르면 끝. 쉽죠?

앱스토어 URL: https://apps.apple.com/kr/app/아주대학교-프린터/id1644664565
## How to Use? (만화로 그렸어요)
https://github.com/KyoungsueKim/super-parakeet/blob/main/COMIC.md
## Prerequisite (managed by CocoaPods)
* `Alamofire`
* `Google-Mobile-Ads-SDK`
## Installation
### 해당 iOS 애플리케이션 프로젝트는 xcode로 작성되었습니다. 실행하기 위해 xcode 16 이상의 버전이 필요합니다. 
* 해당 프로젝트를 아래 커맨드를 이용해 clone 하고 폴더 안의 **"super-parakeet.xcworkspace"** 를 xcode로 오픈하세요. **super-parakeet.xcodeproj** 파일이 아닙니다. 
파일명 끝이 xcworkspace인지 꼭 확인하세요. (swift의 패키지 매니저인 CocoaPods와 관련있습니다. 마치 Python의 pip처럼요. 자세한 내용을 알고싶다면 https://zeddios.tistory.com/25를 참조하세요)
```
git clone https://github.com/KyoungsueKim/super-parakeet
cd super-parakeet
```
* 그 뒤 실행버튼을 눌러보세요. iOS 시뮬레이터가 켜지면서 해당 앱이 실행될 것입니다. 
<img width="1174" alt="image" src="https://user-images.githubusercontent.com/61102713/198851078-fb247c78-0562-4a32-9b0d-ef8651bab7c1.png">

* pdf를 처리하는 프린팅 서버의 주소를 바꾸고 싶다면 'super-parakeet/Service/Requests.swift' 파일 안의 url 상수를 변경하세요. 해당 서버를 돌리기 위한 도커 컨테이너는 https://github.com/KyoungsueKim/verbose-waffle 를 확인하시기 바랍니다.
