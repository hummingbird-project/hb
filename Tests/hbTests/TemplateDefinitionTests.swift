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
                "questions": {
                    "start": {
                        "question":"What is your name?",
                        "text":{
                            "prompt": "Your name",
                            "validationRules": ["nonEmpty", "allASCII"],
                            "contextKey": "name"
                        }
                    }
                },
                "version": 2
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions["start"]?.type
                == .text(
                    .init(
                        prompt: "Your name",
                        validationRules: [.nonEmpty, .allASCII],
                        contextKey: "name"
                    )
                )
        )
    }

    @Test func invalidTextValidationRule() throws {
        let template = """
            {
                "questions": {
                    "start": {
                        "question":"What is your name?",
                        "text":{
                            "prompt": "Your name",
                            "validationRules": ["allUppercase", "allASCII"],
                            "contextKey": "name"
                        }
                    }
                },
                "version": 2
            }
            """
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        }
    }

    @Test func branchQuestion() throws {
        let template = """
            {
                "questions": {
                    "start": {
                        "question":"What do you want to do?",
                        "branch":{
                            "options": [
                                {"name":"tennis", "contextKey": "tennis", "next":"Tennis"},
                                {"name":"football", "contextKey": "football"},
                            ]
                        }
                    }
                },
                "version": 2
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions["start"]?.type
                == .branch(
                    .init(
                        options: [
                            .init(name: "tennis", contextKey: "tennis", next: "Tennis"),
                            .init(name: "football", contextKey: "football"),
                        ]
                    )
                )
        )
    }

    @Test func singleChoiceQuestion() throws {
        let template = """
            {
                "questions": {
                    "start": {
                        "question":"What do you want to do?",
                        "select":{
                            "options": [
                                {"name":"tennis", "displayName": "Tennis"},
                                {"name":"football", "displayName": "Football"},
                            ],
                            "contextKey": "sport",
                            "next": "more"
                        }
                    }
                },
                "version": 2
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions["start"]?.type
                == .singleChoice(
                    .init(
                        contextKey: "sport",
                        options: [
                            .init(name: "tennis", displayName: "Tennis"),
                            .init(name: "football", displayName: "Football"),
                        ],
                        next: "more"
                    )
                )
        )

    }

    @Test func multipleChoiceQuestion() throws {
        let template = """
            {
                "questions": {
                    "start": {
                        "question":"What do you want to do?",
                        "multi-select":{
                            "options": [
                                {"name":"tennis", "contextKey": "Tennis"},
                                {"name":"football", "contextKey": "Football"},
                            ],
                            "next": "more"
                        }
                    }
                },
                "version": 2
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        #expect(
            templateDefinition.questions["start"]?.type
                == .multipleChoice(
                    .init(
                        options: [
                            .init(name: "tennis", contextKey: "Tennis"),
                            .init(name: "football", contextKey: "Football"),
                        ],
                        next: "more"
                    )
                )
        )
    }
}
