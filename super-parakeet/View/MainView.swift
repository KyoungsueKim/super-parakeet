//
//  ContentView.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/11.
//

import SwiftUI
import Messages

struct MainView: View {
    @State var phoneNumber: String = ""
    @State var isLogin: Bool = false
    
    @ObservedObject var printJobs = PrintJobs.instance

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "printer")
                .resizable()
                .frame(width: 120, height: 120, alignment: .center)
                .padding(.top, 100)
            
            Text("Ajou University Printing System")
                .modifier(TextModifier(font: UIConfiguration.titleFont,
                                       color: UIConfiguration.ajouColor))
                .padding(.horizontal, 60)
            
            // if not login
            if (!isLogin) {
                loginStack(phoneNumber: $phoneNumber, isLogin: $isLogin)
                
                GoogleAdView()
                    .frame(width: UIScreen.main.bounds.width > 400 ? 400 : UIScreen.main.bounds.width, height: 50, alignment: .center)
            }
            // if login
            else {
                VStack(spacing: 20){
                    printStack(phoneNumber: $phoneNumber, isLogin: $isLogin)
                    
                    List {
                        ForEach(printJobs.GetJobs(), id: \.self) { url in
                            let documentName = (url as NSString).lastPathComponent.removingPercentEncoding!
                            documentElement(icon: "doc.plaintext", documentName: "\(documentName)")
                        }
                        .onDelete(perform: removeRows)
                    }
                    .lineSpacing(20)
                    .cornerRadius(13)
                    .padding(.horizontal, 15)
                    .frame(width: .infinity, alignment: .center)
                    .refreshable {
                        printJobs.objectWillChange.send()
                    }
                    
                    GoogleAdView()
                        .frame(width: UIScreen.main.bounds.width > 400 ? 400 : UIScreen.main.bounds.width, height: 50, alignment: .center)
                        .padding(.bottom, 15)
                }
            }
        }
        .offset(y: isLogin ? 0 : -100)
        .animation(.easeInOut)
    }
    
    func removeRows(at offsets: IndexSet) {
        PrintJobs.instance.RemoveJob(index: offsets.first!)
    }
}


struct loginStack: View{
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


struct printStack: View{
    @Binding var phoneNumber: String
    @Binding var isLogin: Bool
    
    @State private var showingProgressView = false
    
    @ObservedObject var printJobs = PrintJobs.instance
    
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
                    guard PrintJobs.instance.GetJobs().count != 0 else { return }
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

struct documentElement: View {
    var icon: String
    var documentName: String
    
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
        }
        .frame(alignment: .center)
        
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
