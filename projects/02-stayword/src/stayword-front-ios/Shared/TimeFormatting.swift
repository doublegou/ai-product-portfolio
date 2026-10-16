import Foundation

extension TimeInterval {
    var audioTimestamp: String {
        let total = max(0, Int(self.rounded(.down)))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    var recordingTimestamp: String {
        let totalHundredths = Int((max(0, self) * 100).rounded())
        let hundredths = totalHundredths % 100
        let totalSeconds = totalHundredths / 100
        let seconds = totalSeconds % 60
        let minutes = totalSeconds / 60
        return String(format: "%02d:%02d.%02d", minutes, seconds, hundredths)
    }
}
