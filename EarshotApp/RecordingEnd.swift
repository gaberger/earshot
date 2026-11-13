import Foundation

/// How a capture ended (ADR-2611101015). Pure logic, tested without UI.
enum RecordingEnd: Equatable {
    case stopped
    case failed(String)
    case endedByItself(String)

    static func classify(stopRequested: Bool, error: NSError?) -> RecordingEnd {
        let finished = error?.userInfo["AVErrorRecordingSuccessfullyFinishedKey"] as? Bool
        let diskFull = error?.domain == "AVFoundationErrorDomain" && error?.code == -11807
        if stopRequested {
            guard let error, finished != true else { return .stopped }
            return .failed("The recording may be incomplete: "
                + (diskFull ? "this Mac's disk is full. Free some space before recording again."
                            : error.localizedDescription))
        }
        if diskFull {
            return .endedByItself("Recording stopped: this Mac's disk is full. The audio up to that point is kept. Free some space before recording again.")
        }
        if let error {
            return .endedByItself("Recording stopped by itself: \(error.localizedDescription). The audio up to that point is kept.")
        }
        return .endedByItself("Recording stopped by itself, perhaps because the microphone was disconnected. The audio up to that point is kept.")
    }
}
