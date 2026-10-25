import ClipGumCore
import UIKit
import UniformTypeIdentifiers

/// Share Sheet Action Extension. It reads only NSExtensionItem attachments;
/// there is no general-pasteboard access or background ingestion path.
final class ActionViewController: UIViewController {
    private let cleaner = MobileCleaningService()
    private var originalText = ""
    private var outputText = ""
    private let inputView = UITextView()
    private let outputView = UITextView()
    private let statusLabel = UILabel()
    private let maximumSharedTextBytes = 2 * 1_024 * 1_024

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        inputView.isEditable = false
        outputView.isEditable = false
        statusLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .caption1)
        let stack = UIStackView(arrangedSubviews: [
            makeLabel("Shared text"), inputView,
            makeLabel("Cleaned preview"), outputView, statusLabel,
            makeButton("Clean", action: #selector(clean)),
            makeButton("Scrub secrets", action: #selector(scrub)),
            makeButton("Strip tracking URLs", action: #selector(strip)),
            makeButton("Return cleaned text", action: #selector(finish))
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            inputView.heightAnchor.constraint(equalToConstant: 120),
            outputView.heightAnchor.constraint(equalToConstant: 120)
        ])
        loadSharedText()
    }

    private func loadSharedText() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return }
        let providers = items.compactMap(\.attachments).flatMap { $0 }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            statusLabel.text = "No plain-text Share Sheet item was supplied."
            return
        }
        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
            guard let text = (item as? String) ?? (item as? NSString).map({ $0 as String }) else {
                return
            }
            DispatchQueue.main.async {
                guard let self else { return }
                guard text.utf8.count <= self.maximumSharedTextBytes else {
                    self.statusLabel.text = "The shared text exceeds the 2 MiB mobile boundary; it was not processed."
                    return
                }
                self.originalText = text
                self.inputView.text = text
                self.statusLabel.text = "Choose a local cleaning action, then return the preview."
            }
        }
    }

    @objc private func clean() {
        outputText = cleaner.clean(originalText).output
        outputView.text = outputText
    }

    @objc private func scrub() {
        outputText = cleaner.scrubSecrets(originalText).output
        outputView.text = outputText
    }

    @objc private func strip() {
        outputText = cleaner.stripURLTracking(originalText).output
        outputView.text = outputText
    }

    @objc private func finish() {
        guard !outputText.isEmpty else {
            statusLabel.text = "Choose a cleaning action before returning text."
            return
        }
        let provider = NSItemProvider(
            item: outputText as NSString,
            typeIdentifier: UTType.plainText.identifier
        )
        let item = NSExtensionItem()
        item.attachments = [provider]
        extensionContext?.completeRequest(returningItems: [item], completionHandler: nil)
    }

    private func makeLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .headline)
        return label
    }

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
}
