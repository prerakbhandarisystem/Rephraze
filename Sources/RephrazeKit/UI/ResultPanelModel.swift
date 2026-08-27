import SwiftUI

/// State of the floating picker.
@MainActor
public final class ResultPanelModel: ObservableObject {

    public enum State {
        case loading
        case ready(RephraseSet)
        case failed(String)
    }

    @Published public var state: State = .loading
    @Published public var appName: String = ""

    /// Called when the user picks one.
    public var onChoose: ((RephraseVariant, String) -> Void)?
    public var onCancel: (() -> Void)?

    public init() {}

    public func choose(_ variant: RephraseVariant) {
        guard case let .ready(set) = state else { return }
        guard let text = set.variants[variant] else { return }
        onChoose?(variant, text)
    }

    /// Pick by number key, 1-4.
    public func chooseByDigit(_ digit: Int) {
        guard case let .ready(set) = state else { return }
        let options = set.available
        guard digit >= 1, digit <= options.count else { return }
        let option = options[digit - 1]
        onChoose?(option.variant, option.text)
    }
}
