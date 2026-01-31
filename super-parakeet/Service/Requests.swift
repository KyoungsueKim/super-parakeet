//
//  Requests.swift
//  super-parakeet
//
//  Created by 김경수 on 2022/08/15.
//

import Foundation
import Alamofire

/// 업로드 요청에 필요한 정보.
struct UploadJob: Hashable {
    /// 동일 문서의 진행률 집계를 위한 식별자(보통 원본 URL 문자열).
    let id: String
    /// 업로드할 로컬 파일 URL.
    let fileURL: URL
    /// A3 출력 여부.
    let isA3: Bool
}

/// 업로드 진행 상태.
struct UploadProgress: Equatable {
    /// 성공한 업로드 개수.
    let successCount: Int
    /// 전체 업로드 개수.
    let totalCount: Int
    /// 문서별 완료 수량.
    let completedJobs: [String: Int]
}

/// 업로드 실패 사유.
enum UploadError: LocalizedError {
    /// 파일 URL이 잘못된 경우.
    case invalidFileURL(String)
    /// 파일이 존재하지 않는 경우.
    case fileNotFound(URL)
    /// 서버가 2xx 이외의 상태 코드를 반환한 경우.
    case httpStatus(code: Int, message: String?)
    /// 네트워크/전송 오류.
    case network(AFError)
    /// 알 수 없는 오류.
    case unknown

    /// 사용자에게 보여줄 수 있는 오류 메시지.
    var errorDescription: String? {
        switch self {
        case .invalidFileURL(let value):
            return "파일 경로가 올바르지 않습니다: \(value)"
        case .fileNotFound(let url):
            return "파일을 찾을 수 없습니다: \(url.lastPathComponent)"
        case .httpStatus(let code, let message):
            if let message = message, !message.isEmpty {
                return "서버 오류가 발생했습니다. (HTTP \(code)) \(message)"
            }
            return "서버 오류가 발생했습니다. (HTTP \(code))"
        case .network:
            return "네트워크 오류가 발생했습니다."
        case .unknown:
            return "알 수 없는 오류가 발생했습니다."
        }
    }
}

/// 업로드 요청을 전송하는 클라이언트의 추상화.
protocol UploadRequesting {
    /// 단일 문서 업로드를 수행한다.
    /// - Parameters:
    ///   - job: 업로드할 문서 정보.
    ///   - phoneNumber: 사용자 전화번호.
    ///   - completion: 결과 콜백.
    func upload(job: UploadJob, phoneNumber: String, completion: @escaping (Result<Void, UploadError>) -> Void)
}

/// Alamofire 기반 업로드 클라이언트.
final class AlamofireUploadClient: UploadRequesting {
    private let endpointURL = URL(string: "https://print.kksoft.kr/upload_file/")!

    func upload(job: UploadJob, phoneNumber: String, completion: @escaping (Result<Void, UploadError>) -> Void) {
        guard job.fileURL.isFileURL else {
            completion(.failure(.invalidFileURL(job.fileURL.absoluteString)))
            return
        }

        guard FileManager.default.fileExists(atPath: job.fileURL.path) else {
            completion(.failure(.fileNotFound(job.fileURL)))
            return
        }

        let parameters: [String: Any] = [
            "phone_number": phoneNumber,
            "is_a3": job.isA3
        ]

        AF.upload(multipartFormData: { multipartFormData in
            for (key, value) in parameters {
                multipartFormData.append("\(value)".data(using: .utf8)!, withName: key)
            }
            multipartFormData.append(job.fileURL, withName: "file")
        }, to: endpointURL)
        .validate(statusCode: 200..<300)
        .responseData { response in
            if let error = response.error {
                if let statusCode = response.response?.statusCode {
                    let message = Self.normalizedServerMessage(from: response.data)
                    completion(.failure(.httpStatus(code: statusCode, message: message)))
                    return
                }

                if let afError = error.asAFError {
                    completion(.failure(.network(afError)))
                } else {
                    completion(.failure(.unknown))
                }
                return
            }

            completion(.success(()))
        }
    }

    private static func normalizedServerMessage(from data: Data?) -> String? {
        guard let data = data, let raw = String(data: data, encoding: .utf8) else {
            return nil
        }

        let trimmed = raw
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.lowercased().contains("<html") {
            return nil
        }

        if trimmed.count > 120 {
            let index = trimmed.index(trimmed.startIndex, offsetBy: 120)
            return String(trimmed[..<index]) + "…"
        }

        return trimmed.isEmpty ? nil : trimmed
    }
}

/// 여러 문서를 순차적으로 업로드하고 진행 상태를 제공하는 유즈케이스.
final class UploadJobsUseCase {
    private let uploader: UploadRequesting
    private let stateQueue = DispatchQueue(label: "UploadJobsUseCase.state")

    init(uploader: UploadRequesting = AlamofireUploadClient()) {
        self.uploader = uploader
    }

    /// 문서 목록을 업로드한다.
    /// - Parameters:
    ///   - jobs: 업로드할 문서 목록.
    ///   - phoneNumber: 사용자 전화번호.
    ///   - onProgress: 진행 상태 콜백(메인 스레드에서 호출).
    ///   - onCompletion: 전체 성공/실패 콜백(메인 스레드에서 호출).
    func start(
        jobs: [UploadJob],
        phoneNumber: String,
        onProgress: @escaping (UploadProgress) -> Void,
        onCompletion: @escaping (Result<UploadProgress, UploadError>) -> Void
    ) {
        let totalCount = jobs.count
        if totalCount == 0 {
            let progress = UploadProgress(successCount: 0, totalCount: 0, completedJobs: [:])
            DispatchQueue.main.async {
                onCompletion(.success(progress))
            }
            return
        }

        var successCount = 0
        var completedJobs: [String: Int] = [:]
        for job in jobs {
            completedJobs[job.id] = 0
        }

        var hasFinished = false

        for job in jobs {
            uploader.upload(job: job, phoneNumber: phoneNumber) { [stateQueue] result in
                stateQueue.async {
                    guard !hasFinished else { return }

                    switch result {
                    case .success:
                        successCount += 1
                        completedJobs[job.id, default: 0] += 1
                        let progress = UploadProgress(
                            successCount: successCount,
                            totalCount: totalCount,
                            completedJobs: completedJobs
                        )
                        DispatchQueue.main.async {
                            onProgress(progress)
                        }
                        if successCount == totalCount {
                            hasFinished = true
                            DispatchQueue.main.async {
                                onCompletion(.success(progress))
                            }
                        }
                    case .failure(let error):
                        hasFinished = true
                        DispatchQueue.main.async {
                            onCompletion(.failure(error))
                        }
                    }
                }
            }
        }
    }
}
