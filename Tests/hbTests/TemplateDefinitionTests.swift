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
                            "context": {"set": "name"}
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
                        context: [.set("name")]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["name": "Adam"])
        var context: Context = .init()
        try templateDefinition.updateContext(&context, responder: responder)
        #expect(context["name"] == .string("Adam"))
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
                            "context": {"set": "name"}
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
                                {"name":"tennis", "context": [{"set": "tennis"}, {"set": "sport"}], "next":"surface"},
                                {"name":"football", "context": [{"set": "football"}, {"set": "sport"}]},
                            ]
                        }
                    },
                    {
                        "id": "surface",
                        "question":"What surface do you want to play on?",
                        "branch":{
                            "options": [
                                {"name":"grass", "context": {"set": "grass"}},
                                {"name":"clay", "context": {"set": "clay"}},
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
                            .init(name: "tennis", context: [.set("tennis"), .set("sport")], next: "surface"),
                            .init(name: "football", context: [.set("football"), .set("sport")]),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis"])
        var context: Context = [:]
        try templateDefinition.updateContext(&context, responder: responder)
        #expect(context["tennis"] == .string("1"))
        #expect(context["grass"] == .string("1"))
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
                            "context": {"set": "sport"}
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
                        context: [.set("sport")],
                        options: [
                            .init(name: "tennis", displayName: "Tennis"),
                            .init(name: "football", displayName: "Football"),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis"])
        var context: Context = [:]
        try templateDefinition.updateContext(&context, responder: responder)
        #expect(context["sport"] == .string("tennis"))
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
                                {"name":"tennis", "context": {"set": "Tennis"}},
                                {"name":"football", "context": {"set": "Football"}},
                                {"name":"golf", "context": {"set": "Golf"}},
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
                            .init(name: "tennis", context: [.set("Tennis")]),
                            .init(name: "football", context: [.set("Football")]),
                            .init(name: "golf", context: [.set("Golf")]),
                        ]
                    )
                )
        )
        let responder = DictionaryResponder(answers: ["activity": "tennis,football"])
        var context: Context = [:]
        try templateDefinition.updateContext(&context, responder: responder)
        #expect(context["Tennis"] == .string("1"))
        #expect(context["Football"] == .string("1"))
    }

    @Test
    func testAppendToVariable() throws {
        let template = """
            {
                "questions": [
                    {
                        "id": "activity",
                        "question":"What do you want to do?",
                        "multi-select":{
                            "options": [
                                {"name":"tennis", "context": [{"set": "Tennis"}, {"append": {"key": "sports", "value": "TENNIS"}}]},
                                {"name":"football", "context": [{"set": "Football"}, {"append": {"key": "sports", "value": "FOOTBALL"}}]},
                            ],
                            "next": "activity2"
                        }
                    },
                    {
                        "id": "activity2",
                        "question":"And after?",
                        "multi-select":{
                            "options": [
                                {"name":"swimming", "context": [{"set": "Swimming"}, {"append": {"key": "sports", "value": "SWIMMING"}}]},
                                {"name":"cycling", "context": [{"set": "Cycling"}, {"append": {"key": "sports", "value": {"type": "CYCLING", "class": "road"}}}]},
                            ]
                        }
                    },
                ],
                "version": 3
            }
            """
        let templateDefinition = try JSONDecoder().decode(TemplateDefinition.self, from: Data(template.utf8))
        let responder = DictionaryResponder(answers: ["activity": "tennis", "activity2": "cycling"])
        var context: Context = [:]
        try templateDefinition.updateContext(&context, responder: responder)
        #expect(context["sports"] == .array([.string("TENNIS"), .map(["type": .string("CYCLING"), "class": .string("road")])]))
    }
}
