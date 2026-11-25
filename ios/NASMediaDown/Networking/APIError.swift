import Foundation

/// 统一的接口错误。
struct APIError: LocalizedError, Equatable {
    /// HTTP 状态码；网络或解析错误为 0。
    let status: Int
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }

    static let notConnected = APIError(status: 0, message: "尚未连接到服务器")
    static let invalidServer = APIError(status: 0, message: "服务器地址无效")

    /// 把任意错误转换为可展示的中文文案。
    static func describe(_ error: Error) -> String {
        if let apiError = error as? APIError {
            return apiError.message
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "无法连接到服务器，请检查地址与网络"
            case .timedOut:
                return "请求超时，请稍后重试"
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络连接已断开"
            case .secureConnectionFailed:
                return "HTTPS 连接失败，请确认服务器证书或改用 HTTP"
            case .appTransportSecurityRequiresSecureConnection:
                return "系统阻止了不安全的连接"
            case .cancelled:
                return "请求已取消"
            default:
                return urlError.localizedDescription
            }
        }
        if error is DecodingError {
            return "服务器返回了无法解析的数据"
        }
        return error.localizedDescription
    }
}
