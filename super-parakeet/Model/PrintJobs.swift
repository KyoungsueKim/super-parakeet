//
//  PrintJob.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/20.
//

import Foundation

class PrintJobs: ObservableObject {
    static let instance = PrintJobs()
    
    private var jobQuantities: [String: Int] = [:]
    private var jobIsA3: [String: Bool] = [:]
    
    func GetJobs() -> [String] {
        return UserDefaults.shared.stringArray(forKey: "printQueue") ?? []
    }
    
    func GetJobQuantity(url: String) -> Int {
        return jobQuantities[url] ?? 1
    }
    
    func SetJobQuantity(url: String, quantity: Int) {
        jobQuantities[url] = quantity
    }
    
    func GetJobIsA3(url: String) -> Bool {
        return jobIsA3[url] ?? false
    }
    
    func SetJobIsA3(url: String, isA3: Bool) {
        jobIsA3[url] = isA3
    }
    
    func AddJobs(url: String) {
        var printJobs = GetJobs()
        printJobs.append(url)
        UserDefaults.shared.set(printJobs, forKey: "printQueue")
        self.objectWillChange.send()
    }
    
    func RemoveJob(index: Int){
        var printJobs = GetJobs()
        let url = printJobs[index]
        jobQuantities.removeValue(forKey: url)
        jobIsA3.removeValue(forKey: url)
        printJobs.remove(at: index)
        UserDefaults.shared.set(printJobs, forKey: "printQueue")
        self.objectWillChange.send()
    }
    
    func DeleteAllJobs() {
        jobQuantities.removeAll()
        jobIsA3.removeAll()
        UserDefaults.shared.removeObject(forKey: "printQueue")
        self.objectWillChange.send()
    }
}
