import Foundation

/// 界面展示用的格式化工具。
enum Format {
    /// 把字节数格式化为易读文本。
    static func bytes(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        if value < 1024 { return "\(Int(value)) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var size = value / 1024
        var unit = 0
        while size >= 1024 && unit < units.count - 1 {
            size /= 1024
            unit += 1
        }
        return String(format: size >= 100 ? "%.0f %@" : "%.1f %@", size, units[unit])
    }

    /// 把字节数格式化为易读文本。
    static func bytes(_ value: Int64?) -> String {
        bytes(value.map(Double.init))
    }

    /// 把秒数格式化为时长，如 1:02:03。
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite else { return "—" }
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 把下载速度格式化为 MB/s 文本。
    static func speed(_ bytesPerSecond: Double?) -> String? {
        guard let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return "\(bytes(bytesPerSecond))/s"
    }

    /// 把剩余秒数格式化为 ETA 文案。
    static func eta(_ seconds: Double?) -> String? {
        guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
        return "剩余 \(duration(seconds))"
    }

    /// 格式化 Unix 时间戳为本地日期时间。
    static func date(_ timestamp: Double?) -> String {
        guard let timestamp, timestamp > 0 else { return "—" }
        return dateFormatter.string(from: Date(timeIntervalSince1970: timestamp))
    }

    /// 格式化百分比。
    static func percent(_ progress: Double) -> String {
        "\(Int((min(1, max(0, progress)) * 100).rounded()))%"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter
    }()
}
