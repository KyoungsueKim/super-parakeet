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
    /// 업로드할 문서가 없는 경우.
    case emptyQueue
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
        case .emptyQueue:
            return "업로드할 문서가 없습니다."
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

/// 업로드 계획 결과를 담는 모델입니다.
struct UploadJobPlan {
    /// 업로드 대상 작업 목록.
    let jobs: [UploadJob]
    /// 전체 업로드 개수.
    let totalCount: Int
    /// 문서별 완료 수량 초기값.
    let completedJobs: [String: Int]
}

/// 프린트 큐 정보를 기반으로 업로드 계획을 생성합니다.
final class UploadJobPlanner {
    /// 프린트 큐 요약 정보를 받아 업로드 작업 목록을 생성합니다.
    /// - Parameter descriptors: 프린트 큐 항목 요약 정보.
    /// - Returns: 업로드 계획 또는 오류.
    func makePlan(from descriptors: [PrintJobDescriptor]) -> Result<UploadJobPlan, UploadError> {
        guard descriptors.isEmpty == false else {
            return .failure(.emptyQueue)
        }

        var uploadJobs: [UploadJob] = []
        var completedJobs: [String: Int] = [:]

        for descriptor in descriptors {
            guard let fileURL = URL(string: descriptor.urlString) else {
                return .failure(.invalidFileURL(descriptor.urlString))
            }

            completedJobs[descriptor.urlString] = 0
            let quantity = max(descriptor.quantity, 1)
            for _ in 0..<quantity {
                uploadJobs.append(UploadJob(id: descriptor.urlString, fileURL: fileURL, isA3: descriptor.isA3))
            }
        }

        if uploadJobs.isEmpty {
            return .failure(.emptyQueue)
        }

        return .success(
            UploadJobPlan(
                jobs: uploadJobs,
                totalCount: uploadJobs.count,
                completedJobs: completedJobs
            )
        )
    }
}

/// 업로드 요청을 전송하는 클라이언트의 추상화.
protocol UploadRequesting {
    /// 단일 문서 업로드를 수행한다.
    /// - Parameters:
    ///   - job: 업로드할 문서 정보.
    ///   - phoneNumber: 사용자 전화번호.
    /// - Throws: 업로드 실패 또는 취소 오류.
    func upload(job: UploadJob, phoneNumber: String) async throws
}

/// Alamofire 기반 업로드 클라이언트.
final class AlamofireUploadClient: UploadRequesting {
    private let endpointURL = URL(string: "https://print.kksoft.kr/upload_file/")!

    func upload(job: UploadJob, phoneNumber: String) async throws {
        guard job.fileURL.isFileURL else {
            throw UploadError.invalidFileURL(job.fileURL.absoluteString)
        }

        guard FileManager.default.fileExists(atPath: job.fileURL.path) else {
            throw UploadError.fileNotFound(job.fileURL)
        }

        let parameters: [String: Any] = [
            "phone_number": phoneNumber,
            "is_a3": job.isA3
        ]

        let uploadRequest = AF.upload(multipartFormData: { multipartFormData in
            for (key, value) in parameters {
                multipartFormData.append("\(value)".data(using: .utf8)!, withName: key)
            }
            multipartFormData.append(job.fileURL, withName: "file")
        }, to: endpointURL)
        .validate(statusCode: 200..<300)
        let response = await withTaskCancellationHandler {
            uploadRequest.cancel()
        } operation: {
            await uploadRequest.serializingData().response
        }

        if let error = response.error {
            if let statusCode = response.response?.statusCode {
                let message = Self.normalizedServerMessage(from: response.data)
                throw UploadError.httpStatus(code: statusCode, message: message)
            }

            if let afError = error.asAFError {
                if afError.isExplicitlyCancelledError {
                    throw CancellationError()
                }
                throw UploadError.network(afError)
            }
            throw UploadError.unknown
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

/// 여러 문서를 업로드하고 진행 상태를 제공하는 유즈케이스.
final class UploadJobsUseCase {
    private let uploader: UploadRequesting

    init(uploader: UploadRequesting = AlamofireUploadClient()) {
        self.uploader = uploader
    }

    /// 문서 목록을 업로드한다.
    /// - Parameters:
    ///   - jobs: 업로드할 문서 목록.
    ///   - phoneNumber: 사용자 전화번호.
    ///   - onProgress: 진행 상태 콜백.
    /// - Returns: 최종 업로드 진행 상태.
    /// - Throws: 업로드 실패 또는 취소 오류.
    func start(
        jobs: [UploadJob],
        phoneNumber: String,
        onProgress: @escaping @Sendable (UploadProgress) async -> Void
    ) async throws -> UploadProgress {
        guard jobs.isEmpty == false else {
            throw UploadError.emptyQueue
        }

        let totalCount = jobs.count
        var initialCompletedJobs: [String: Int] = [:]
        for job in jobs {
            initialCompletedJobs[job.id, default: 0] = 0
        }

        let accumulator = UploadProgressAccumulator(
            totalCount: totalCount,
            completedJobs: initialCompletedJobs
        )

        var lastProgress: UploadProgress?

        do {
            try await withThrowingTaskGroup(of: String.self) { group in
                for job in jobs {
                    group.addTask {
                        try Task.checkCancellation()
                        try await self.uploader.upload(job: job, phoneNumber: phoneNumber)
                        return job.id
                    }
                }

                for try await jobId in group {
                    let progress = await accumulator.recordSuccess(for: jobId)
                    lastProgress = progress
                    await onProgress(progress)
                }
            }
        } catch {
            throw error
        }

        return lastProgress ?? UploadProgress(
            successCount: 0,
            totalCount: totalCount,
            completedJobs: initialCompletedJobs
        )
    }
}

/// 업로드 진행 상태를 안전하게 합산하는 액터입니다.
actor UploadProgressAccumulator {
    private let totalCount: Int
    private var successCount: Int = 0
    private var completedJobs: [String: Int]

    init(totalCount: Int, completedJobs: [String: Int]) {
        self.totalCount = totalCount
        self.completedJobs = completedJobs
    }

    /// 성공한 작업을 반영하고 새로운 진행 상태를 반환합니다.
    /// - Parameter jobId: 완료된 작업의 식별자.
    func recordSuccess(for jobId: String) -> UploadProgress {
        successCount += 1
        completedJobs[jobId, default: 0] += 1
        return UploadProgress(
            successCount: successCount,
            totalCount: totalCount,
            completedJobs: completedJobs
        )
    }
}
