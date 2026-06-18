//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Noora

protocol TemplateOption: CustomStringConvertible, Equatable {
    var name: String { get }
}

/// Define questions and parameters for template
struct TemplateDefinition: Decodable {
    static let currentVersion: Int = 3

    struct Question: Decodable, Equatable {
        enum ContextTransform: Decodable, Equatable {
            case set(String)

            init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if container.contains(.set) {
                    self = .set(try container.decode(String.self, forKey: .set))
                } else {
                    throw DecodingError.typeMismatch(
                        String.self,
                        .init(codingPath: decoder.codingPath, debugDescription: "Failed to decode Rule enum.")
                    )
                }
            }

            func updateContext(_ context: inout [String: String], value: String) throws {
                switch self {
                case .set(let key):
                    context[key] = value
                }
            }

            private enum CodingKeys: String, CodingKey {
                case set
            }
        }

        struct ContextTransformGroup: Decodable, Equatable, ExpressibleByArrayLiteral {
            let transforms: [ContextTransform]

            init(transforms: [ContextTransform]) {
                self.transforms = transforms
            }

            init(arrayLiteral elements: ContextTransform...) {
                self.transforms = elements
            }

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let transforms = try? container.decode([ContextTransform].self) {
                    self.transforms = transforms
                } else if let transform = try? container.decode(ContextTransform.self) {
                    self.transforms = [transform]
                } else if let key = try? container.decode(String.self) {
                    self.transforms = [.set(key)]
                } else {
                    throw DecodingError.typeMismatch(
                        ContextTransformGroup.self,
                        .init(codingPath: decoder.codingPath, debugDescription: "Failed to decode ContextTransformGroup")
                    )
                }
            }

            func updateContext(_ context: inout [String: String], value: String) throws {
                for transform in self.transforms {
                    try transform.updateContext(&context, value: value)
                }
            }
        }

        enum QuestionType: Decodable, Equatable {
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
            struct Text: Decodable, Equatable {
                let prompt: String
                let description: String?
                let validationRules: [ValidationRule]
                let context: ContextTransformGroup
                let next: String?

                init(
                    prompt: String,
                    description: String? = nil,
                    validationRules: [ValidationRule],
                    context: ContextTransformGroup,
                    next: String? = nil
                ) {
                    self.prompt = prompt
                    self.description = description
                    self.validationRules = validationRules
                    self.context = context
                    self.next = next
                }
            }
            struct Branch: Decodable, Equatable {
                struct Option: TemplateOption, Decodable, Equatable {
                    let name: String
                    let displayName: String?
                    let context: ContextTransformGroup
                    let next: String?

                    var description: String { self.displayName ?? self.name }

                    internal init(name: String, displayName: String? = nil, context: ContextTransformGroup = [], next: String? = nil) {
                        self.name = name
                        self.displayName = displayName
                        self.context = context
                        self.next = next
                    }

                    init(from decoder: any Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)

                        self.name = try container.decode(String.self, forKey: .name)
                        self.displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
                        self.context = try container.decodeIfPresent(ContextTransformGroup.self, forKey: .context) ?? []
                        self.next = try container.decodeIfPresent(String.self, forKey: .next)
                    }

                    private enum CodingKeys: CodingKey {
                        case name
                        case displayName
                        case context
                        case next
                    }
                }
                let description: String?
                let options: [Option]

                init(description: String? = nil, options: [Option]) {
                    self.description = description
                    self.options = options
                }
            }
            struct SingleChoice: Decodable, Equatable {
                struct Option: TemplateOption, Decodable, Equatable {
                    let name: String
                    let displayName: String?
                    var description: String { self.displayName ?? self.name }

                    init(name: String, displayName: String? = nil) {
                        self.name = name
                        self.displayName = displayName
                    }
                }
                let description: String?
                let context: ContextTransformGroup
                let options: [Option]
                let next: String?

                init(
                    description: String? = nil,
                    context: ContextTransformGroup,
                    options: [Option],
                    next: String? = nil
                ) {
                    self.description = description
                    self.context = context
                    self.options = options
                    self.next = next
                }
            }
            struct MultipleChoice: Decodable, Equatable {
                struct Option: TemplateOption, Decodable, Equatable {
                    let name: String
                    let displayName: String?
                    let context: ContextTransformGroup
                    var description: String { self.displayName ?? self.name }

                    init(name: String, displayName: String? = nil, context: ContextTransformGroup) {
                        self.name = name
                        self.displayName = displayName
                        self.context = context
                    }
                }
                let options: [Option]
                let next: String?

                init(options: [Option], next: String? = nil) {
                    self.options = options
                    self.next = next
                }
            }
            case text(Text)
            case branch(Branch)
            case singleChoice(SingleChoice)
            case multipleChoice(MultipleChoice)
        }
        let id: String
        let question: String
        let type: QuestionType

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decode(String.self, forKey: .id)
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
            case id
            case question
            case text
            case branch
            case singleChoice = "select"
            case multipleChoice = "multi-select"
        }
    }

    let version: Int
    let questions: [Question]
    let ignore: [String]

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        guard self.version <= Self.currentVersion else {
            throw HBError("The metadata.json file expects a later version of hb. Upgrade hb to use this template.")
        }
        self.questions = try container.decode([Question].self, forKey: .questions)
        self.ignore = try container.decodeIfPresent([String].self, forKey: .ignore) ?? ["metadata.json"]
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case questions
        case rules
        case ignore
    }

    func updateContext(_ context: inout [String: String], responder: some Responder) throws {
        var id: String? = self.questions.first?.id
        while let _id = id {
            guard let question = self.questions.first(where: { $0.id == _id }) else { throw HBError("Invalid metadata id: \(_id)") }
            id = try responder.updateContext(&context, question: question)
        }
    }
}
