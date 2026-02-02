//
//  UploadProgressModalView.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/23.
//

import Foundation
import SwiftUI
import AVFoundation

enum ModalViewState {
    case PROGRESS
    case SUCCESS
    case FAILED
}

struct UploadStatusModalView: View {
    var phoneNumber: String
    
    @State var errorMessage: String?
    @State var onSuccessCount: Int = 0
    @State var totalCount: Int = 0
    
    @State var modalViewState: ModalViewState = .PROGRESS
    
    
    var body: some View {
        switch modalViewState {
            case .PROGRESS:
                UploadProgressView(phoneNumber: phoneNumber, onSuccessCount: $onSuccessCount, errorMessage: $errorMessage, modalViewState: $modalViewState)
            case .SUCCESS:
                UploadSuccessView()
            case .FAILED:
                UploadFailedView(errorMessage: $errorMessage)
        }
    }
}

struct UploadProgressView: View {
    @Environment(\.presentationMode) var presentation: Binding<PresentationMode>
    
    var phoneNumber: String
    @Binding var onSuccessCount: Int
    @Binding var errorMessage: String?
    @Binding var modalViewState: ModalViewState
    
    @State var totalCount: Int = 0
    @State var completedJobs: [String: Int] = [:]
    
    var body: some View{
        VStack (spacing: 15){
            Image(systemName: "square.and.arrow.up.on.square")
                .resizable()
                .frame(width: 70, height: 80, alignment: .center)
                .onAppear(){
                    HapticManager.instance.notification(type: .warning)
                }

            Text("Upload pdf to the server... (\(onSuccessCount)/\(totalCount))")
                .modifier(TextModifier(font: UIConfiguration.titleFont,
                                   color: UIConfiguration.ajouColor))
                .padding(.horizontal, 60)
            
            Text("문서가 업로드 될 때 까지 잠시만 기달려주세요. (문서 크기가 크면 시간이 오래 걸릴 수 있습니다)")
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 60)
            
            Button(action: {
                presentation.wrappedValue.dismiss()
            }) {
                Text("Cancel")
                    .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                             color: UIConfiguration.ajouColor,
                                             textColor: .white,
                                             width: 100,
                                             height: 35,
                                             cornerRadious: 10))
            }
        }.onAppear() {
            let descriptors = PrintJobQueue.shared.jobDescriptors()
            let planner = UploadJobPlanner()

            switch planner.makePlan(from: descriptors) {
            case .failure(let error):
                errorMessage = error.localizedDescription
                modalViewState = .FAILED
            case .success(let plan):
                totalCount = plan.totalCount
                completedJobs = plan.completedJobs

                let useCase = UploadJobsUseCase()
                useCase.start(jobs: plan.jobs, phoneNumber: phoneNumber, onProgress: { progress in
                onSuccessCount = progress.successCount
                totalCount = progress.totalCount
                completedJobs = progress.completedJobs
                }, onCompletion: { result in
                    switch result {
                    case .success:
                        modalViewState = .SUCCESS
                        PrintJobQueue.shared.removeAllJobs()
                    case .failure(let error):
                        errorMessage = error.localizedDescription
                        modalViewState = .FAILED
                    }
                })
            }
        }
    }
}

struct UploadSuccessView: View {
    @Environment(\.presentationMode) var presentation: Binding<PresentationMode>

    
    var body: some View{
        VStack (spacing: 15){
            Image(systemName: "checkmark.circle")
                .resizable()
                .frame(width: 80, height: 80, alignment: .center)
                .onAppear(){
                    HapticManager.instance.notification(type: .success)
                    AudioServicesPlaySystemSound(1407)
                }

            Text("Successfully Send Documents to printers")
                .modifier(TextModifier(font: UIConfiguration.titleFont,
                                   color: UIConfiguration.ajouColor))
                .padding(.horizontal, 60)
            
            Text("프린터기에서 휴대폰 번호를 입력 후 추가된 문서를 확인하세요.")
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 60)
            
            Button(action: {
                presentation.wrappedValue.dismiss()
            }) {
                Text("Close")
                    .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                             color: UIConfiguration.ajouColor,
                                             textColor: .white,
                                             width: 100,
                                             height: 35,
                                             cornerRadious: 10))
            }

        }
    }
}

struct UploadFailedView: View {
    @Environment(\.presentationMode) var presentation: Binding<PresentationMode>

    @Binding var errorMessage: String?
    
    var body: some View{
        VStack (spacing: 15){
            Image(systemName: "xmark.seal")
                .resizable()
                .frame(width: 80, height: 80, alignment: .center)
                .onAppear(){
                    HapticManager.instance.notification(type: .error)
                    AudioServicesPlaySystemSound(1006)
                }

            Text("Failed to send pdf to Server")
                .modifier(TextModifier(font: UIConfiguration.titleFont,
                                   color: UIConfiguration.ajouColor))
            
            Text("오류가 발생했습니다.")
                .modifier(TextModifier(font: UIConfiguration.middleFont))
                .padding(.horizontal, 60)
            
            if let message = errorMessage{
                Text(message)
                    .modifier(TextModifier(font: UIConfiguration.middleFont))
                    .padding(.horizontal, 60)
                    .lineLimit(10)
            }

            Button(action: {
                presentation.wrappedValue.dismiss()
            }) {
                Text("Close")
                    .modifier(ButtonModifier(font: UIConfiguration.buttonFont,
                                             color: UIConfiguration.ajouColor,
                                             textColor: .white,
                                             width: 100,
                                             height: 35,
                                             cornerRadious: 10))
            }
        }
    }
}

struct UploadProgressModalView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            UploadStatusModalView(phoneNumber: "01083729703")
                .previewInterfaceOrientation(.portrait)
        }
    }
}
