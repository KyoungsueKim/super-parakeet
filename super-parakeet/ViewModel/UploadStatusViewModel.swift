//
//  UploadStatusViewModel.swift
//  super-parakeet
//
//  Created by Codex on 2026/02/03.
//

import Foundation
import Combine

/// 업로드 진행 상태를 화면에 전달하는 뷰 모델입니다.
@MainActor
final class UploadStatusViewModel: ObservableObject {
    /// 현재 표시 중인 모달 상태입니다.
    @Published var state: ModalViewState = .PROGRESS
    /// 성공한 업로드 개수입니다.
    @Published var onSuccessCount: Int = 0
    /// 전체 업로드 개수입니다.
    @Published var totalCount: Int = 0
    /// 문서별 완료 수량입니다.
    @Published var completedJobs: [String: Int] = [:]
    /// 실패 시 표시할 오류 메시지입니다.
    @Published var errorMessage: String?

    private let queue: PrintJobQueue
    private let planner: UploadJobPlanner
    private let useCase: UploadJobsUseCase
    private var uploadTask: Task<Void, Never>?
    private var hasStarted: Bool = false
    private var acknowledgedCounts: [String: Int] = [:]

    /// 의존성을 주입해 초기화합니다.
    /// - Parameters:
    ///   - queue: 프린트 큐.
    ///   - planner: 업로드 계획 생성기.
    ///   - useCase: 업로드 유즈케이스.
    init(
        queue: PrintJobQueue = .shared,
        planner: UploadJobPlanner = UploadJobPlanner(),
        useCase: UploadJobsUseCase = UploadJobsUseCase()
    ) {
        self.queue = queue
        self.planner = planner
        self.useCase = useCase
    }

    deinit {
        uploadTask?.cancel()
    }

    /// 업로드를 한 번만 시작합니다.
    /// - Parameter phoneNumber: 사용자 전화번호.
    func startIfNeeded(phoneNumber: String) {
        guard hasStarted == false else { return }
        hasStarted = true
        start(phoneNumber: phoneNumber)
    }

    /// 업로드 작업을 시작합니다.
    /// - Parameter phoneNumber: 사용자 전화번호.
    func start(phoneNumber: String) {
        guard queue.beginUpload() else {
            errorMessage = "다른 업로드가 완료되거나 취소될 때까지 기다려 주세요."
            state = .FAILED
            return
        }
        queue.reload()
        if let error = queue.errorMessage { queue.endUpload(); errorMessage = error; state = .FAILED; return }
        acknowledgedCounts = [:]
        let descriptors = queue.jobDescriptors()
        switch planner.makePlan(from: descriptors) {
        case .failure(let error):
            queue.endUpload()
            errorMessage = error.localizedDescription
            state = .FAILED
            return
        case .success(let plan):
            totalCount = plan.totalCount
            completedJobs = plan.completedJobs

            uploadTask = Task { [self] in
                defer { self.queue.endUpload() }
                do {
                    _ = try await useCase.start(
                        jobs: plan.jobs,
                        phoneNumber: phoneNumber
                    ) { [self] progress in
                        try await MainActor.run {
                            for (key, count) in progress.completedJobs {
                                let previous = self.acknowledgedCounts[key, default: 0]
                                if count > previous, let id = UUID(uuidString: key) {
                                    try self.queue.acknowledgeUpload(id: id, count: count - previous)
                                    self.acknowledgedCounts[key] = count
                                }
                            }
                            self.onSuccessCount = progress.successCount
                            self.totalCount = progress.totalCount
                            self.completedJobs = progress.completedJobs
                        }
                    }

                    self.state = .SUCCESS

                } catch is CancellationError {
                    self.errorMessage = "업로드를 취소했습니다. 완료된 수량은 목록에서 차감하고 남은 문서는 보존했습니다."
                    self.state = .FAILED
                } catch {
                    self.errorMessage = error.localizedDescription
                    self.state = .FAILED
                }
            }
        }
    }

    /// 진행 중인 업로드 작업을 취소합니다.
    func cancel() {
        uploadTask?.cancel()
        uploadTask = nil
    }
}
