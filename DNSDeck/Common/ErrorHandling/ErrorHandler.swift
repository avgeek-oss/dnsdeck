import Combine
import Foundation
import SwiftUI

@MainActor
class ErrorHandler: ObservableObject {
    @Published var currentError: AppError?
    @Published var isShowingError = false

    func handle(_ error: Error) {
        let appError: AppError = if let existingAppError = error as? AppError {
            existingAppError
        } else {
            .unknown(error)
        }

        currentError = appError
        isShowingError = true

        Logger.logError(error, context: "ErrorHandler")
    }

    func clearError() {
        currentError = nil
        isShowingError = false
    }
}

extension View {
    func withErrorHandling(_ errorHandler: ErrorHandler) -> some View {
        alert(
            "Error",
            isPresented: Binding(
                get: { errorHandler.isShowingError },
                set: { _ in errorHandler.clearError() }
            )
        ) {
            Button("OK") {
                errorHandler.clearError()
            }
        } message: {
            Text(errorHandler.currentError?.localizedDescription ?? "An unknown error occurred")
        }
    }
}
