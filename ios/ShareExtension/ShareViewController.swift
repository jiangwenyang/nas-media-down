import UIKit
import UniformTypeIdentifiers

/// 分享扩展：接收其他应用分享的链接，转交主应用直接探测。
final class ShareViewController: UIViewController {
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let linkLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let cancelButton = UIButton(type: .system)

    private var sharedLink: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        configureView()
        Task { await loadSharedLink() }
    }

    // MARK: - 界面

    private func configureView() {
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 0, height: 250)

        titleLabel.text = "发送到媒体下载"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        statusLabel.text = "正在读取分享的链接…"
        statusLabel.font = .preferredFont(forTextStyle: .subheadline)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        linkLabel.font = .preferredFont(forTextStyle: .footnote)
        linkLabel.textColor = .tertiaryLabel
        linkLabel.numberOfLines = 2
        linkLabel.lineBreakMode = .byTruncatingMiddle
        linkLabel.isHidden = true

        var actionConfig = UIButton.Configuration.filled()
        actionConfig.title = "正在读取…"
        actionConfig.cornerStyle = .large
        actionConfig.baseBackgroundColor = view.tintColor
        actionButton.configuration = actionConfig
        actionButton.isEnabled = false
        actionButton.addTarget(self, action: #selector(startProbe), for: .touchUpInside)
        actionButton.heightAnchor.constraint(equalToConstant: 48).isActive = true

        var cancelConfig = UIButton.Configuration.plain()
        cancelConfig.title = "取消"
        cancelConfig.baseForegroundColor = .secondaryLabel
        cancelButton.configuration = cancelConfig
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [
            titleLabel, statusLabel, linkLabel, actionButton, cancelButton,
        ])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(18, after: linkLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20),
        ])
    }

    private func updateActionTitle(_ title: String) {
        var config = actionButton.configuration ?? .filled()
        config.title = title
        actionButton.configuration = config
    }

    // MARK: - 动作

    /// 读取分享项中的网页链接。
    private func loadSharedLink() async {
        let items = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        let link = await Self.extractLink(from: items)

        if let link {
            sharedLink = link.absoluteString
            statusLabel.text = "确认后将打开「媒体下载」直接开始探测。"
            linkLabel.text = link.absoluteString
            linkLabel.isHidden = false
            actionButton.isEnabled = true
            updateActionTitle("开始探测")
        } else {
            statusLabel.text = "没有找到可用的网页链接，请在分享时选择链接或网页。"
            actionButton.isEnabled = false
            updateActionTitle("无法读取链接")
        }
    }

    @objc private func startProbe() {
        guard let sharedLink, let deepLink = Self.deepLink(for: sharedLink) else { return }

        actionButton.isEnabled = false
        updateActionTitle("正在打开…")

        extensionContext?.open(deepLink) { [weak self] opened in
            Task { @MainActor in
                guard let self else { return }
                if opened {
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                } else {
                    self.actionButton.isEnabled = true
                    self.updateActionTitle("开始探测")
                    self.statusLabel.text = "无法打开「媒体下载」，请确认应用已安装后重试。"
                }
            }
        }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(
            withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        )
    }

    // MARK: - 解析

    /// 依次尝试分享项中的 URL 与纯文本，返回第一个可探测的网页链接。
    private static func extractLink(from items: [NSExtensionItem]) async -> URL? {
        for item in items {
            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = await provider.sharedValue(UTType.url.identifier),
                   let link = link(from: value) {
                    return link
                }
                if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let value = await provider.sharedValue(UTType.plainText.identifier),
                   let link = link(from: value) {
                    return link
                }
            }
        }
        return nil
    }

    private static func link(from value: Any) -> URL? {
        if let url = value as? URL, isSupported(url) { return url }
        if let string = value as? String { return firstLink(in: string) }
        if let data = value as? Data, let string = String(data: data, encoding: .utf8) {
            return firstLink(in: string)
        }
        return nil
    }

    private static func firstLink(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), isSupported(url) { return url }

        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        return detector.firstMatch(in: trimmed, options: [], range: range)?.url
    }

    private static func isSupported(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// 生成主应用的深链接，供下载页直接探测。
    private static func deepLink(for link: String) -> URL? {
        var components = URLComponents()
        components.scheme = "nasmediadown"
        components.host = "probe"
        components.queryItems = [URLQueryItem(name: "url", value: link)]
        return components.url
    }
}

private extension NSItemProvider {
    /// 以 async/await 方式读取分享项内容。
    func sharedValue(_ typeIdentifier: String) async -> Any? {
        await withCheckedContinuation { continuation in
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { value, _ in
                continuation.resume(returning: value)
            }
        }
    }
}
