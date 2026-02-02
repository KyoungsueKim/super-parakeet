//
//  UploadStatusViewModel.swift
//  super-parakeet
//
//  Created by Codex on 2026/02/03.
//

import Foundation

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
        let descriptors = queue.jobDescriptors()
        switch planner.makePlan(from: descriptors) {
        case .failure(let error):
            errorMessage = error.localizedDescription
            state = .FAILED
            return
        case .success(let plan):
            totalCount = plan.totalCount
            completedJobs = plan.completedJobs

            uploadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    _ = try await useCase.start(
                        jobs: plan.jobs,
                        phoneNumber: phoneNumber
                    ) { [weak self] progress in
                        await MainActor.run {
                            self?.onSuccessCount = progress.successCount
                            self?.totalCount = progress.totalCount
                            self?.completedJobs = progress.completedJobs
                        }
                    }

                    self.state = .SUCCESS
                    self.queue.removeAllJobs()
                } catch is CancellationError {
                    return
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
