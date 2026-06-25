//
// This source file is part of the Hummingbird server framework project
// Copyright (c) the Hummingbird authors
//
// See LICENSE.txt for license information
// SPDX-License-Identifier: Apache-2.0
//

import Foundation
import Testing

@testable import hb

struct TemplateDefinitionTests {
    @Test
    func laterVersion() {
        let template = #"{"version": 999, "questions": {}}"#
        #expect(throws: HBError("The metadata.json file expects a later version of hb. Upgrade hb to use this template.")) {
            try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        }
    }

    @Test func textQuestion() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "name",
                        "question":"What is your name?",
                        "text":{
                            "prompt": "Your name",
                            "validationRules": ["nonEmpty", "allASCII"],
                            "contextKey": "name"
                        }
                    }
                ],
                "version": 2
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions.first?.type
                == .text(
                    .init(
                        prompt: "Your name",
                        validationRules: [.nonEmpty, .allASCII],
                        contextKey: "name"
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["name": "Adam"])
        var context: [String: String] = [:]
        try templateDefinition.constructContext(&context, responder: responder)
        #expect(context["name"] == "Adam")
    }

    @Test func invalidTextValidationRule() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "name",
                        "question":"What is your name?",
                        "text":{
                            "prompt": "Your name",
                            "validationRules": ["allUppercase", "allASCII"],
                            "contextKey": "name"
                        }
                    }
                ],
                "version": 3
            }
            """
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        }
    }

    @Test func branchQuestion() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "activity",
                        "question":"What do you want to do?",
                        "branch":{
                            "options": [
                                {"name":"tennis", "contextKey": "tennis", "next":"surface"},
                                {"name":"football", "contextKey": "football"},
                            ]
                        }
                    },
                    {
                        "id": "surface",
                        "question":"What surface do you want to play on?",
                        "branch":{
                            "options": [
                                {"name":"grass", "contextKey": "grass"},
                                {"name":"clay", "contextKey": "clay"},
                            ]
                        }
                    }
                ],
                "version": 3
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions.first?.type
                == .branch(
                    .init(
                        options: [
                            .init(name: "tennis", contextKey: "tennis", next: "surface"),
                            .init(name: "football", contextKey: "football"),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis"])
        var context: [String: String] = [:]
        try templateDefinition.constructContext(&context, responder: responder)
        #expect(context["tennis"] == "1")
        #expect(context["grass"] == "1")
    }

    @Test func singleChoiceQuestion() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "activity",
                        "question":"What do you want to do?",
                        "select":{
                            "options": [
                                {"name":"tennis", "displayName": "Tennis"},
                                {"name":"football", "displayName": "Football"},
                            ],
                            "contextKey": "sport"
                        }
                    }
                ],
                "version": 3
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions.first?.type
                == .singleChoice(
                    .init(
                        contextKey: "sport",
                        options: [
                            .init(name: "tennis", displayName: "Tennis"),
                            .init(name: "football", displayName: "Football"),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis"])
        var context: [String: String] = [:]
        try templateDefinition.constructContext(&context, responder: responder)
        #expect(context["sport"] == "tennis")
    }

    @Test func multipleChoiceQuestion() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "activity",
                        "question":"What do you want to do?",
                        "multi-select":{
                            "options": [
                                {"name":"tennis", "contextKey": "Tennis"},
                                {"name":"football", "contextKey": "Football"},
                                {"name":"golf", "contextKey": "Golf"},
                            ]
                        }
                    }
                ],
                "version": 3
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions.first?.type
                == .multipleChoice(
                    .init(
                        options: [
                            .init(name: "tennis", contextKey: "Tennis"),
                            .init(name: "football", contextKey: "Football"),
                            .init(name: "golf", contextKey: "Golf"),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis,football"])
        var context: [String: String] = [:]
        try templateDefinition.constructContext(&context, responder: responder)
        #expect(context["Tennis"] == "1")
        #expect(context["Football"] == "1")
    }
}
