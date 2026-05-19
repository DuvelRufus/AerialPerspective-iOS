//
//  ScoringService.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation

enum ScoreLevel {
    case strong, note, risk
}

struct DomainScore {
    let domain: Domain
    let score: Int
    let level: ScoreLevel
}

struct ScoringService {

    static func compute(
        answers: [UUID: UUID],
        questions: [Question],
        options: [AnswerOption]
    ) -> [DomainScore] {
        let scoreByOption = Dictionary(
            uniqueKeysWithValues: options.map { ($0.id, $0.score) }
        )
        let questionsByDomain = Dictionary(grouping: questions, by: { $0.domain })

        return Domain.allCases.map { domain in
            let domainQuestions = questionsByDomain[domain.rawValue] ?? []
            var sum = 0
            var count = 0
            for q in domainQuestions {
                if let optId = answers[q.id],
                   let score = scoreByOption[optId] {
                    sum += score
                    count += 1
                }
            }
            let score = count == 0 ? 0 : Int((Double(sum) / Double(count)).rounded())
            return DomainScore(domain: domain, score: score, level: level(for: score))
        }
    }

    static func delta(
        current: [DomainScore],
        previous: [DomainScore]
    ) -> [Domain: Int] {
        let prevMap = Dictionary(uniqueKeysWithValues: previous.map { ($0.domain, $0.score) })
        var result: [Domain: Int] = [:]
        for d in current {
            result[d.domain] = d.score - (prevMap[d.domain] ?? 0)
        }
        return result
    }

    static func level(for score: Int) -> ScoreLevel {
        if score >= 66 { return .strong }
        if score >= 34 { return .note }
        return .risk
    }
}
