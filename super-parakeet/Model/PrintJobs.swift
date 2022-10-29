//
//  PrintJob.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/20.
//

import Foundation

class PrintJobs: ObservableObject {
    static let instance = PrintJobs()
    
    func GetJobs() -> [String] {
        return UserDefaults.shared.stringArray(forKey: "printQueue") ?? []
    }
    
    func AddJobs(url: String) {
        var printJobs = GetJobs()
        printJobs.append(url)
        UserDefaults.shared.set(printJobs, forKey: "printQueue")
        self.objectWillChange.send()
    }
    
    func RemoveJob(index: Int){
        var printJobs = GetJobs()
        printJobs.remove(at: index)
        UserDefaults.shared.set(printJobs, forKey: "printQueue")
        self.objectWillChange.send()
    }
    
    func DeleteAllJobs() {
        UserDefaults.shared.removeObject(forKey: "printQueue")
        self.objectWillChange.send()
    }
}
