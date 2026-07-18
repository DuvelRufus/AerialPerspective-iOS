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

    /// Case-insensitive match: domain strings from model output arrive in
    /// varying casing ("tech" vs "Tech"), and rawValue matching misses them.
    init?(caseInsensitive raw: String) {
        let lowered = raw.lowercased()
        guard let match = Domain.allCases.first(where: { $0.rawValue.lowercased() == lowered }) else {
            return nil
        }
        self = match
    }
}

// MARK: - Project

struct Project: Identifiable, Codable, Hashable {
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

// Hashable: navigationDestination(item:) pushes require it (as Project for the path).
struct Assessment: Identifiable, Codable, Hashable {
    let id: UUID
    var projectId: UUID
    var version: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case version
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
    // String, not Domain, so an unexpected DB value can't fail decoding.
    var domain: String?
    var suggestedAction: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case assessmentId = "assessment_id"
        case title
        case content
        case riskLevel = "risk_level"
        case domain
        case suggestedAction = "suggested_action"
        case createdAt = "created_at"
    }
}

// MARK: - Plan rows (plans / plan_actions tables)

/// A generated plan as a row. Archived plans keep isActive == false; a
/// partial unique index guarantees at most one active plan per assessment.
struct Plan: Identifiable, Codable {
    let id: UUID
    var assessmentId: UUID
    var summary: String
    var focusDay1_30: String
    var focusDay31_60: String
    var focusDay61_90: String
    var isActive: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, summary
        case assessmentId = "assessment_id"
        case focusDay1_30 = "focus_day1_30"
        case focusDay31_60 = "focus_day31_60"
        case focusDay61_90 = "focus_day61_90"
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

/// One plan action row — the stable identity actions.plan_action_id points
/// at. `phase` stays a String so an unexpected DB value can't fail decoding.
struct PlanActionRow: Identifiable, Codable {
    let id: UUID
    var planId: UUID
    var phase: String
    var text: String
    var domain: String?
    var sortOrder: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, phase, text, domain
        case planId = "plan_id"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}
