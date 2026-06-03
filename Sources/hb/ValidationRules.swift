import Noora

struct NoWhitespaceValidationRule: ValidatableRule {
    let error: any ValidatableError

    func validate(input: String) -> Bool {
        return !input.contains(where: \.isWhitespace)
    }
}

struct AsciiValidationRule: ValidatableRule {
    let error: any ValidatableError

    func validate(input: String) -> Bool {
        return !input.contains(where: { !$0.isASCII })
    }
}
