//
//  Test.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/15.
//

import Foundation
import Alamofire
import SwiftUI

func SendJobsToServer(jobs: [String], phoneNumber: String, onSuccessCount: Binding<Int>, errorMessage: Binding<String?>, modalViewState: Binding<ModalViewState>) ->  Void {
    for job in jobs {
        HttpRequest(urlString: job, phoneNumber: phoneNumber, onSuccessCount: onSuccessCount, errorMessage: errorMessage, modalViewState: modalViewState)
    }
}

private func HttpRequest(urlString: String, phoneNumber: String, onSuccessCount: Binding<Int>, errorMessage: Binding<String?>, modalViewState: Binding<ModalViewState>) {
    
//    let ip = "http://192.168.0.76"
//    let port = "64550"
//    let url = URL(string: "\(ip):\(port)/upload_file/")
    
    let url = URL(string: "https://print.kksoft.kr:64550/upload_file/")
    var fileURL = URL(string: urlString)
    let parameters: [String : Any] = [
        "phone_number": phoneNumber
    ]

    if let fileURL = fileURL, let url = url {
        do{
            let data = try Data(contentsOf: fileURL)
            AF.upload(multipartFormData: { multipartFormData in
                for (key, value) in parameters {
                    multipartFormData.append("\(value)".data(using: .utf8)!, withName: key)
                }
                multipartFormData.append(fileURL, withName: "file")
            }, to: url)
                .response { response in
                    switch response.result {
                         case .success:
                            onSuccessCount.wrappedValue += 1
                        
                            // All Jobs are success
                            if onSuccessCount.wrappedValue == PrintJobs.instance.GetJobs().count {
                                modalViewState.wrappedValue = .SUCCESS
                                PrintJobs.instance.DeleteAllJobs()
                                PrintJobs.instance.objectWillChange.send()
                            }
                        
                         case .failure(let error):
                            errorMessage.wrappedValue = error.errorDescription
                            modalViewState.wrappedValue = .FAILED
                            print(error)
                    }
                    
                    debugPrint(response)
                }
        }
        catch {
            errorMessage.wrappedValue = error.localizedDescription
            modalViewState.wrappedValue = .FAILED
            return
        }
    }
}
