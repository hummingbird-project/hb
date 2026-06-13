//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Noora

/// Define questions and parameters for template
struct TemplateDefinition: Decodable {
    static let currentVersion: Int = 2

    struct Question: Decodable {
        enum QuestionType: Decodable {
            enum ValidationRule: String, Decodable {
                case nonEmpty
                case noWhitespace
                case allASCII

                var rule: ValidatableRule {
                    switch self {
                    case .nonEmpty: NonEmptyValidationRule(error: "String cannot be empty.")
                    case .noWhitespace: NoWhitespaceValidationRule(error: "String cannot contain whitespace")
                    case .allASCII: AsciiValidationRule(error: "String cannot contain non-ASCII values.")
                    }
                }
            }
            struct Text: Decodable {
                let prompt: String
                let description: String?
                let validationRules: [ValidationRule]
                let contextKey: String
                let next: String?
            }
            struct Branch: Decodable {
                struct Option: Decodable, CustomStringConvertible, Equatable {
                    let name: String
                    let displayName: String?
                    let contextKey: String?
                    let next: String?

                    var description: String { self.displayName ?? self.name }
                }
                let description: String?
                let options: [Option]
            }
            struct SingleChoice: Decodable {
                struct Option: Decodable, CustomStringConvertible, Equatable {
                    let name: String
                    let displayName: String?

                    var description: String { self.displayName ?? self.name }
                }
                let description: String?
                let contextKey: String
                let options: [Option]
                let next: String?
            }
            struct MultipleChoice: Decodable {
                struct Option: Decodable, CustomStringConvertible, Equatable {
                    let name: String
                    let contextKey: String

                    var description: String { self.name }
                }
                let options: [Option]
                let next: String?
            }
            case text(Text)
            case branch(Branch)
            case singleChoice(SingleChoice)
            case multipleChoice(MultipleChoice)
        }
        let question: String
        let type: QuestionType

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.question = try container.decode(String.self, forKey: .question)
            if container.contains(.text) {
                self.type = .text(try container.decode(QuestionType.Text.self, forKey: .text))
            } else if container.contains(.singleChoice) {
                self.type = .singleChoice(try container.decode(QuestionType.SingleChoice.self, forKey: .singleChoice))
            } else if container.contains(.branch) {
                self.type = .branch(try container.decode(QuestionType.Branch.self, forKey: .branch))
            } else if container.contains(.multipleChoice) {
                self.type = .multipleChoice(try container.decode(QuestionType.MultipleChoice.self, forKey: .multipleChoice))
            } else {
                throw DecodingError.typeMismatch(
                    QuestionType.self,
                    .init(codingPath: decoder.codingPath, debugDescription: "Failed to decode QuestionType enum.")
                )
            }
        }
        private enum CodingKeys: String, CodingKey {
            case question
            case text
            case branch
            case singleChoice = "select"
            case multipleChoice = "multi-select"
        }
    }
    let version: Int
    let questions: [String: Question]
    let ignore: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        guard self.version <= Self.currentVersion else {
            throw HBError("The metadata.json file expects a later version of hb. Upgrade hb to use this template.")
        }
        self.questions = try container.decode([String: Question].self, forKey: .questions)
        self.ignore = try container.decodeIfPresent([String].self, forKey: .ignore) ?? ["metadata.json"]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case questions
        case ignore
    }

    func constructContext(_ context: inout [String: String]) throws {
        var id: String? = "start"
        while let _id = id {
            guard let question = self.questions[_id] else { throw HBError("Invalid metadata id: \(_id)") }
            switch question.type {
            case .text(let text):
                let answer = Noora().textPrompt(
                    title: "\(question.question)",
                    prompt: "\(text.prompt)",
                    description: text.description.map { "\($0)" },
                    validationRules: text.validationRules.map(\.rule)
                )
                context[text.contextKey] = answer
                id = text.next
            case .branch(let options):
                let choice = Noora().singleChoicePrompt(
                    question: "\(question.question)",
                    options: options.options,
                    description: options.description.map { "\($0)" }
                )
                if let contextKey = choice.contextKey {
                    context[contextKey] = "yes"
                }
                id = choice.next
            case .singleChoice(let singleChoice):
                let choice = Noora().singleChoicePrompt(
                    question: "\(question.question)",
                    options: singleChoice.options,
                    description: singleChoice.description.map { "\($0)" }
                )
                context[singleChoice.contextKey] = choice.name
                id = singleChoice.next
            case .multipleChoice(let multipleChoice):
                let choices = Noora().multipleChoicePrompt(
                    question: "\(question.question)",
                    options: multipleChoice.options,
                )
                for choice in choices {
                    context[choice.contextKey] = "yes"
                }
                id = multipleChoice.next
            }
        }
    }
}
