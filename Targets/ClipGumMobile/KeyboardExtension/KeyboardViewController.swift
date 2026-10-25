import ClipGumCore
import UIKit

/// Optional keyboard. It never observes pasteboard changes and never reads in
/// viewDidLoad; the sole read is inside this explicit button action.
final class KeyboardViewController: UIInputViewController {
    private let cleaner = MobileCleaningService()

    override func viewDidLoad() {
        super.viewDidLoad()
        let button = UIButton(type: .system)
        button.setTitle("Paste Clean", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.addTarget(self, action: #selector(pasteCleanTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    @objc private func pasteCleanTapped() {
        // Explicit user interaction is required for this pasteboard read.
        guard let text = UIPasteboard.general.string,
              text.utf8.count <= 2 * 1_024 * 1_024 else { return }
        let cleaned = cleaner.clean(text).output
        textDocumentProxy.insertText(cleaned)
    }
}
