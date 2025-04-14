//
//  Test.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/15.
//

import Foundation
import Alamofire
import SwiftUI

func SendJobsToServer(jobs: [String], phoneNumber: String, onSuccessCount: Binding<Int>, errorMessage: Binding<String?>, modalViewState: Binding<ModalViewState>, completedJobs: Binding<[String: Int]>) ->  Void {
    for job in jobs {
        let quantity = PrintJobs.instance.GetJobQuantity(url: job)
        for _ in 0..<quantity {
            HttpRequest(urlString: job, phoneNumber: phoneNumber, jobs: jobs, onSuccessCount: onSuccessCount, errorMessage: errorMessage, modalViewState: modalViewState, completedJobs: completedJobs)
        }
    }
}

private func HttpRequest(urlString: String, phoneNumber: String, jobs: [String], onSuccessCount: Binding<Int>, errorMessage: Binding<String?>, modalViewState: Binding<ModalViewState>, completedJobs: Binding<[String: Int]>) {
    
//    let ip = "http://192.168.0.76"
//    let port = "64550"
//    let url = URL(string: "\(ip):\(port)/upload_file/")
    
    let url = URL(string: "https://print.kksoft.kr:64550/upload_file/")
    var fileURL = URL(string: urlString)
    let parameters: [String : Any] = [
        "phone_number": phoneNumber,
        "is_a3": PrintJobs.instance.GetJobIsA3(url: urlString)
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
                            DispatchQueue.main.async {
                                onSuccessCount.wrappedValue += 1
                                completedJobs.wrappedValue[urlString, default: 0] += 1
                                
                                // All Jobs are success
                                if onSuccessCount.wrappedValue == jobs.reduce(0, { $0 + PrintJobs.instance.GetJobQuantity(url: $1) }) {
                                    modalViewState.wrappedValue = .SUCCESS
                                    PrintJobs.instance.DeleteAllJobs()
                                    PrintJobs.instance.objectWillChange.send()
                                }
                            }
                        
                         case .failure(let error):
                            DispatchQueue.main.async {
                                errorMessage.wrappedValue = error.errorDescription
                                modalViewState.wrappedValue = .FAILED
                                print(error)
                            }
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
