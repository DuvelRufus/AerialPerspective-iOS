//
//  Untitled.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//


import Foundation

// MARK: - Domain

enum Domain: String, CaseIterable, Codable {
    case team = "Team"
    case process = "Process"
    case product = "Product"
    case tech = "Tech"
    case stakeholders = "Stakeholders"
    case culture = "Culture"
}

// MARK: - Project

struct Project: Identifiable, Codable {
    let id: UUID
    var name: String
    var userId: UUID?
    var durationValue: Int?
    var durationUnit: DurationUnit?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case userId = "user_id"
        case durationValue = "duration_value"
        case durationUnit = "duration_unit"
        case createdAt = "created_at"
    }
}

enum DurationUnit: String, Codable {
    case weeks, months, years
}

// MARK: - Assessment

struct Assessment: Identifiable, Codable {
    let id: UUID
    var projectId: UUID
    var version: Int
    var plan: PlanResult?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case version
        case plan
        case createdAt = "created_at"
    }
}

// MARK: - Question + AnswerOption

struct Question: Identifiable, Codable {
    let id: UUID
    var domain: String
    var questionText: String
    var sortOrder: Int?
    var tooltip: String?

    enum CodingKeys: String, CodingKey {
        case id
        case domain
        case questionText = "question_text"
        case sortOrder = "sort_order"
        case tooltip
    }
}

struct AnswerOption: Identifiable, Codable {
    let id: UUID
    var questionId: UUID
    var label: String
    var score: Int
    var sortOrder: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case questionId = "question_id"
        case label
        case score
        case sortOrder = "sort_order"
    }
}

// MARK: - Answer

struct Answer: Identifiable, Codable {
    let id: UUID
    var assessmentId: UUID
    var questionId: UUID
    var answerOptionId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case assessmentId = "assessment_id"
        case questionId = "question_id"
        case answerOptionId = "answer_option_id"
    }
}

// MARK: - Insight

enum RiskLevel: String, Codable {
    case risk, note, strong
}

struct Insight: Identifiable, Codable {
    let id: UUID
    var assessmentId: UUID
    var title: String?
    var content: String?
    var riskLevel: RiskLevel?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case assessmentId = "assessment_id"
        case title
        case content
        case riskLevel = "risk_level"
        case createdAt = "created_at"
    }
}

// MARK: - Plan

struct PlanPhase: Codable {
    var focus: String
    var actions: [String]
}

struct PlanResult: Codable {
    var summary: String
    var day1_30: PlanPhase
    var day31_60: PlanPhase
    var day61_90: PlanPhase
}
