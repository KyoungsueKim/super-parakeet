//
//  ContentView.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/11.
//

import SwiftUI
import Messages
import UIKit

struct MainView: View {
    @State var phoneNumber: String = ""
    @State var isLogin: Bool = false
    @State private var showRewardedPrompt: Bool = false
    @State private var showRewardResultAlert: Bool = false
    @State private var rewardResultMessage: String = ""
    @State private var earnedRewardMessages: [String] = []
    @State private var didRewardedAdReward: Bool = false
    @State private var didRewardedInterstitialReward: Bool = false
    @State private var didInterstitialAdShown: Bool = false
    @State private var showAppOpenPrompt: Bool = false
    @State private var isAppOpenAdEnabled: Bool = AppOpenAdPreference.isEnabled
    
    @ObservedObject var printJobQueue = PrintJobQueue.shared
    @StateObject private var rewardedAdFlowCoordinator = RewardedAdFlowCoordinator()

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 20) {
                Image(systemName: "printer")
                    .resizable()
                    .frame(width: 120, height: 120, alignment: .center)
                    .padding(.top, 100)
                    .onTapGesture(count: 3) {
                        showRewardedPrompt = true
                    }
                    .onLongPressGesture(minimumDuration: 3) {
                        isAppOpenAdEnabled = AppOpenAdPreference.isEnabled
                        showAppOpenPrompt = true
                    }
                
                Text("Ajou University Printing System")
                    .modifier(TextModifier(font: UIConfiguration.titleFont,
                                           color: UIConfiguration.ajouColor))
                    .padding(.horizontal, 60)
                
                // if not login
                if (!isLogin) {
                    LoginStack(phoneNumber: $phoneNumber, isLogin: $isLogin)
                    
                    BannerAdView()
                        .frame(width: UIScreen.main.bounds.width > 400 ? 400 : UIScreen.main.bounds.width, height: 50, alignment: .center)
                }
                // if login
                else {
                    VStack(spacing: 20){
                        PrintStack(phoneNumber: $phoneNumber, isLogin: $isLogin)
                        
                        ZStack {
                            List {
                                ForEach(printJobQueue.jobs(), id: \.self) { url in
                                    let documentName = url.decodedLastPathComponent
                                    DocumentRow(icon: "doc.plaintext", documentName: "\(documentName)", url: url)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets())
                                }
                                .onDelete(perform: removeRows)
                            }
                            .listStyle(PlainListStyle())
                            .lineSpacing(20)
                            .cornerRadius(13)
                            .padding(.horizontal, 15)
                            .frame(width: UIScreen.main.bounds.width - 30, alignment: .center)
                            .refreshable {
                                printJobQueue.reload()
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 13)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.horizontal, 15)
                        
                        BannerAdView()
                            .frame(width: UIScreen.main.bounds.width > 400 ? 400 : UIScreen.main.bounds.width, height: 50, alignment: .center)
                            .padding(.bottom, 15)
                    }
                }
            }
            
            if isLogin {
                BackToLoginButton(action: moveToLogin)
                    .padding(.leading, 16)
                    .padding(.top, 12)
                    .zIndex(1)
            }
        }
        .offset(y: isLogin ? 0 : -100)
        .animation(.easeInOut, value: isLogin)
        .onAppear {
            printJobQueue.reload()
            rewardedAdFlowCoordinator.preloadAds()
        }
        .confirmationDialog("보상형 광고",
                            isPresented: $showRewardedPrompt,
                            titleVisibility: .visible) {
            Button("광고 시청하고 보상받기") {
                requestRewardedAd()
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("원하는 경우에만 광고를 시청할 수 있습니다.")
        }
        .alert("보상 안내", isPresented: $showRewardResultAlert) {
            Button("확인", role: .cancel) { }
        } message: {
            Text(rewardResultMessage)
        }
        .confirmationDialog("앱 오프닝 광고",
                            isPresented: $showAppOpenPrompt,
                            titleVisibility: .visible) {
            if isAppOpenAdEnabled {
                Button("비활성화", role: .destructive) {
                    setAppOpenAdEnabled(false)
                }
            } else {
                Button("활성화") {
                    setAppOpenAdEnabled(true)
                }
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text(isAppOpenAdEnabled
                 ? "앱 오프닝 광고를 비활성화하시겠습니까?"
                 : "앱 오프닝 광고를 활성화하시겠습니까?")
        }
    }
    
    func removeRows(at offsets: IndexSet) {
        printJobQueue.removeJobs(at: offsets)
    }

    /// 로그인 상태로 이동하기 위해 입력 정보를 초기화합니다.
    private func moveToLogin() {
        KeyboardManager.dismiss()
        phoneNumber = ""
        isLogin = false
    }

    /// 보상형 광고를 요청하고 표시합니다.
    private func requestRewardedAd() {
        guard let rootViewController = UIApplication.shared.topViewController() else {
            rewardResultMessage = "광고를 표시할 화면을 찾지 못했습니다."
            showRewardResultAlert = true
            return
        }

        earnedRewardMessages.removeAll()
        didRewardedAdReward = false
        didRewardedInterstitialReward = false
        didInterstitialAdShown = false

        rewardedAdFlowCoordinator.presentRewardedFlow(from: rootViewController,
                                                      onRewardedAdReward: {
            didRewardedAdReward = true
            earnedRewardMessages.append("보상형 광고 보상이 지급되었습니다.")
        }, onRewardedInterstitialReward: {
            didRewardedInterstitialReward = true
            earnedRewardMessages.append("보상형 전면 광고 보상이 지급되었습니다.")
        }, onInterstitialShown: {
            didInterstitialAdShown = true
        }, onAllAdsUnavailable: {
            rewardResultMessage = "현재 광고를 불러올 수 없습니다. 잠시 후 다시 시도해주세요."
            showRewardResultAlert = true
        }, onFlowFinished: {
            let shouldShowHiddenMessage = didRewardedAdReward
            && didRewardedInterstitialReward
            && didInterstitialAdShown

            if shouldShowHiddenMessage {
                earnedRewardMessages.append("광고를 끝까지 참고 기다려주셔서 정말 감사합니다!! 이 화면을 캡쳐해서 zp5njqlfex@ajou.ac.kr 으로 메일 보내주시면 맛있는 기프티콘을 선물로 드리겠습니다 :)")
            }

            guard earnedRewardMessages.isEmpty == false else { return }
            rewardResultMessage = earnedRewardMessages.joined(separator: "\n")
            showRewardResultAlert = true
        })
    }

    /// 앱 오프닝 광고 활성화 설정을 저장하고 광고 상태를 갱신합니다.
    /// - Parameter isEnabled: 활성화 여부.
    private func setAppOpenAdEnabled(_ isEnabled: Bool) {
        AppOpenAdPreference.isEnabled = isEnabled
        isAppOpenAdEnabled = isEnabled
        let rootViewController = UIApplication.shared.topViewController()
        AppOpenAdManager.shared.updatePreference(isEnabled: isEnabled, viewController: rootViewController)
    }
}

/// 로그인 화면으로 돌아가기 위한 간단한 버튼 뷰입니다.
struct BackToLoginButton: View {
    /// 버튼 탭 시 수행할 동작입니다.
    let action: () -> Void

    var body: some View {
        Button(action: {
            HapticFeedbackManager.lightImpact()
            action()
        }) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(Color(UIConfiguration.ajouColor))
                .padding(8)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.9))
                )
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .accessibilityLabel("로그인 화면으로 돌아가기")
    }
}


/// 로그인 입력 영역을 표시하는 뷰입니다.
struct LoginStack: View{
    @State private var showAlert: Bool = false
    @Binding var phoneNumber: String
    @Binding var isLogin: Bool
    
    var body: some View{
        VStack(spacing: 15){
            Text("휴대폰 번호를 입력하고 로그인 버튼을 누르세요")
                .modifier(TextModifier(font: UIConfiguration.middleFont, color: .label))
                .padding(.horizontal, 60)
            
            HStack {
                TextField("010", text: $phoneNumber)
                    .modifier(TextModifier(font: UIConfiguration.middleFont))
                    .frame(width: 250, height: 35, alignment: .center)
                    .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
                    .keyboardType(.decimalPad)
                
                Button(action: {
                    HapticFeedbackManager.lightImpact()
                    KeyboardManager.dismiss()
                    let pattern = "010[0-9]{8}"
                    guard phoneNumber.count == 11 && phoneNumber.range(of: pattern, options: .regularExpression) != nil else {
                        showAlert = true
                        return
                    }
                    
                    print("phoneNumber: \($phoneNumber)")
                    isLogin = true
                }) {
                    Text("Log In")
                        .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                                 color: UIConfiguration.ajouColor,
                                                 textColor: .white,
                                                 width: 100,
                                                 height: 35,
                                                 cornerRadious: 10))
                }
                .alert(isPresented: $showAlert){
                    Alert(title: Text("안내매시지"), message: Text("올바른 휴대전화 번호를 입력해주세요."), dismissButton: .default(Text("Close")))
                }
            }
        }
    }
}

/// 키보드 제어를 담당하는 유틸리티입니다.
enum KeyboardManager {
    /// 현재 표시 중인 키보드를 내립니다.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
    }
}

/// 햅틱 피드백을 제공하는 유틸리티입니다.
enum HapticFeedbackManager {
    /// 가벼운 탭 피드백을 발생시킵니다.
    static func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}


/// 프린트 요청 및 업로드 진입 영역을 표시하는 뷰입니다.
struct PrintStack: View{
    @Binding var phoneNumber: String
    @Binding var isLogin: Bool
    
    @State private var showingProgressView = false
    
    @ObservedObject var printJobQueue = PrintJobQueue.shared
    
    var body: some View{
        VStack {
            // Info message view
            Text("출력할 문서를 확인하고 Print 버튼을 누르세요. \n(문서가 안보이면 아래 빈 공간을 밑으로 스크롤하세요)")
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 10)
            
            HStack {
                Text("로그인 정보: \(phoneNumber)")
                .modifier(TextModifier(font: UIConfiguration.middleFont,
                                       color: .label))
                .frame(width: 250, height: 35, alignment: .center)
                .background(RoundedRectangle(cornerRadius: 10).stroke(Color.gray, lineWidth: 1))
            
                
                Button(action: {
                    guard printJobQueue.jobs().isEmpty == false else { return }
                    showingProgressView = true
                }){
                    Text("Print")
                        .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                                 color: UIConfiguration.ajouColor,
                                                 textColor: .white,
                                                 width: 100,
                                                 height: 35,
                                                 cornerRadious: 10))
                }
                .sheet(isPresented: $showingProgressView) {
                    UploadStatusModalView(phoneNumber: phoneNumber)
                }
            }
        }
    }
}

/// 프린트 대기 문서 정보를 표시하는 행입니다.
struct DocumentRow: View {
    var icon: String
    var documentName: String
    var url: String
    
    @ObservedObject var printJobQueue = PrintJobQueue.shared
    
    var body: some View {
        HStack (spacing: 15){
            Image(systemName: "\(icon)")
                .font(.system(size: 20))
 
            VStack(alignment: .leading, spacing: 0){
                Divider().opacity(0)
                Text("\(documentName)")
                    .lineLimit(1)
                    .modifier(TextModifier(font: UIConfiguration.listFont))
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // A3/A4 선택 버튼
                Button(action: {
                    let currentIsA3 = printJobQueue.isA3(for: url)
                    printJobQueue.setA3(!currentIsA3, for: url)
                }) {
                    Text(printJobQueue.isA3(for: url) ? "A3" : "A4")
                        .modifier(TextModifier(font: UIConfiguration.listFont))
                        .frame(width: 40)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.gray, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                // 빼기 버튼
                Button(action: {
                    let currentQuantity = printJobQueue.jobQuantity(for: url)
                    if currentQuantity > 1 {
                        printJobQueue.setJobQuantity(currentQuantity - 1, for: url)
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                
                Text("\(printJobQueue.jobQuantity(for: url))")
                    .modifier(TextModifier(font: UIConfiguration.listFont))
                    .frame(width: 30)
                
                // 추가 버튼
                Button(action: {
                    let currentQuantity = printJobQueue.jobQuantity(for: url)
                    printJobQueue.setJobQuantity(currentQuantity + 1, for: url)
                }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MainView()
                .previewInterfaceOrientation(.portrait)
        }
    }
}
