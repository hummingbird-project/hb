//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//
import Noora

/// Protocol defining how we respond to the template definition questions
protocol Responder {
    func updateContext(_ context: inout [String: String], question: TemplateDefinition.Question) throws -> String?
}

/// Respond to template questions based on dictionary of question ids and answers
struct DictionaryResponder: Responder {
    let answers: [String: String]

    func updateContext(_ context: inout [String: String], question: TemplateDefinition.Question) throws -> String? {
        let answer = answers[question.id]
        switch question.type {
        case .text(let text):
            if let answer {
                context[text.contextKey] = answer
            }
            return text.next
        case .branch(let branch):
            let choice =
                if let answer {
                    branch.options.first(where: { $0.name == answer })
                } else {
                    // if no option given then default to first option
                    branch.options.first
                }
            guard let choice else {
                throw HBError("Invalid answer to question: \(question.id)")
            }
            if let contextKey = choice.contextKey {
                context[contextKey] = "1"
            }
            return choice.next
        case .singleChoice(let singleChoice):
            let choice =
                if let answer {
                    singleChoice.options.first(where: { $0.name == answer })
                } else {
                    // if no option given then default to first option
                    singleChoice.options.first
                }
            guard let choice else {
                throw HBError("Invalid answer to question: \(question.id)")
            }
            context[singleChoice.contextKey] = choice.name
            return singleChoice.next
        case .multipleChoice(let multipleChoice):
            if let answer {
                let splitAnswer = answer.split(separator: ",")
                let choices = try splitAnswer.map { answer in
                    guard let choice = multipleChoice.options.first(where: { $0.name == answer }) else {
                        throw HBError("Invalid answer to question: \(question.id)")
                    }
                    return choice
                }
                for choice in choices {
                    context[choice.contextKey] = "1"
                }
            }
            return multipleChoice.next
        }
    }
}

/// Respond to template defintion questions using Noora
struct NooraResponder: Responder {
    func updateContext(_ context: inout [String: String], question: TemplateDefinition.Question) throws -> String? {
        switch question.type {
        case .text(let text):
            let answer = Noora().textPrompt(
                title: "\(question.question)",
                prompt: "\(text.prompt)",
                description: text.description.map { "\($0)" },
                validationRules: text.validationRules.map(\.rule)
            )
            context[text.contextKey] = answer
            return text.next
        case .branch(let options):
            let choice = Noora().singleChoicePrompt(
                question: "\(question.question)",
                options: options.options,
                description: options.description.map { "\($0)" }
            )
            if let contextKey = choice.contextKey {
                context[contextKey] = "1"
            }
            return choice.next
        case .singleChoice(let singleChoice):
            let choice = Noora().singleChoicePrompt(
                question: "\(question.question)",
                options: singleChoice.options,
                description: singleChoice.description.map { "\($0)" }
            )
            context[singleChoice.contextKey] = choice.name
            return singleChoice.next
        case .multipleChoice(let multipleChoice):
            let choices = Noora().multipleChoicePrompt(
                question: "\(question.question)",
                options: multipleChoice.options,
            )
            for choice in choices {
                context[choice.contextKey] = "1"
            }
            return multipleChoice.next
        }
    }
}
