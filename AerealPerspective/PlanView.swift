//
//  PlanView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-19.
//

import Foundation
import UIKit
import SwiftUI
import Supabase

struct PlanView: View {
    var assessment: Assessment
    var project: Project
    var domainScores: [DomainScore]
    var answerStore: AnswerStore
    var questionStore: QuestionStore

    @State private var plan: PlanResult?
    @State private var isGenerating = false
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var actionStore = ActionStore()
    @State private var addedActions: Set<String> = []
    @State private var pendingAction: PendingPlanAction? = nil

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()
            content
        }
        .navigationTitle("30-60-90 Plan")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await loadPlan() }
        .sheet(item: $pendingAction) { pending in
            CreateActionSheet(initialTitle: pending.text, domainScores: domainScores) { title, domain in
                Task { await createAction(title: title, domain: domain, rowText: pending.text) }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isGenerating {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.apOrange)
                Text("Bygger plan...")
                    .foregroundStyle(.apTextSecondary)
                    .font(.subheadline)
            }
        } else if isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .tint(.apOrange)
                Text("Laddar plan...")
                    .foregroundStyle(.apTextSecondary)
                    .font(.subheadline)
            }
        } else if let plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(plan.summary)
                        .foregroundStyle(.apTextSecondary)
                        .font(.subheadline)
                        .padding(.horizontal)

                    phaseCard(title: "Dag 1–30", phase: plan.day1_30)
                    phaseCard(title: "Dag 31–60", phase: plan.day31_60)
                    phaseCard(title: "Dag 61–90", phase: plan.day61_90)

                    generateButton("Uppdatera", style: .secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.apRisk)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
        } else {
            VStack(spacing: 20) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 48))
                    .foregroundStyle(.apOrange)
                Text("Ingen plan ännu")
                    .foregroundStyle(.apTextPrimary)
                    .font(.headline)
                generateButton("Generera 30-60-90 plan")
                if let msg = errorMessage {
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.apRisk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }

    private func phaseCard(title: String, phase: PlanPhase) -> some View {
        APCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.apOrange)
                Text(phase.focus)
                    .font(.subheadline.bold())
                    .foregroundStyle(.apTextPrimary)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(phase.actions.enumerated()), id: \.offset) { i, action in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(i + 1).")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.apOrange)
                                .frame(width: 20, alignment: .trailing)
                            Text(action.text)
                                .font(.caption)
                                .foregroundStyle(.apTextSecondary)
                            Spacer(minLength: 0)
                            if addedActions.contains(action.text) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.apStrong)
                                    .minTapTarget()
                            } else {
                                Button {
                                    handleAdd(action)
                                } label: {
                                    Image(systemName: "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(.apOrange)
                                }
                                .buttonStyle(.plain)
                                .haptic(.medium)
                                .minTapTarget()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private func generateButton(_ label: String, style: APPillButtonStyle = .primary) -> some View {
        APPillButton(title: label, action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await generate() }
        }, style: style)
    }

    private func loadPlan() async {
        if let existing = assessment.plan {
            plan = existing
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched: Assessment = try await supabase
                .from("assessments")
                .select()
                .eq("id", value: assessment.id)
                .single()
                .execute()
                .value
            plan = fetched.plan
        } catch {
            print("PlanView: loadPlan error: \(error)")
        }
    }

    private func generate() async {
        print("PlanView: generate() start – assessment \(assessment.id)")
        errorMessage = nil
        isGenerating = true
        defer {
            isGenerating = false
            print("PlanView: generate() end")
        }
        do {
            let result = try await EdgeFunctionService.generatePlan(
                scores: domainScores,
                answers: answerStore.answers,
                questions: questionStore.questions,
                options: questionStore.options,
                durationValue: project.durationValue,
                durationUnit: project.durationUnit?.rawValue
            )
            print("PlanView: plan received, summary length \(result.summary.count)")
            plan = result
            try await supabase
                .from("assessments")
                .update(AssessmentPlanUpdate(plan: result))
                .eq("id", value: assessment.id)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            print("PlanView: generate error: \(error)")
        }
    }

    // MARK: - Add to actions

    private func handleAdd(_ action: PlanAction) {
        if let raw = action.domain, let domain = Domain(rawValue: raw) {
            Task { await createAction(title: action.text, domain: domain, rowText: action.text) }
        } else {
            pendingAction = PendingPlanAction(text: action.text)
        }
    }

    private func createAction(title: String, domain: Domain, rowText: String) async {
        do {
            try await actionStore.add(
                projectId: project.id,
                domain: domain.rawValue,
                title: title,
                assessmentId: assessment.id,
                createdFromScore: domainScores.first { $0.domain == domain }?.score
            )
            addedActions.insert(rowText)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            errorMessage = error.localizedDescription
            print("PlanView: createAction error: \(error)")
        }
    }
}

private struct PendingPlanAction: Identifiable {
    let text: String
    var id: String { text }
}

private struct AssessmentPlanUpdate: Encodable {
    let plan: PlanResult
}

// MARK: - Create Action Sheet (legacy plans without domain)

private struct CreateActionSheet: View {
    let domainScores: [DomainScore]
    let onSave: (String, Domain) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var domain: Domain

    init(
        initialTitle: String,
        domainScores: [DomainScore],
        onSave: @escaping (String, Domain) -> Void
    ) {
        self.domainScores = domainScores
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _domain = State(initialValue: domainScores.min(by: { $0.score < $1.score })?.domain ?? .team)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.apBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "ÅTGÄRD")
                        TextField("", text: $title)
                            .textFieldStyle(.plain)
                            .foregroundStyle(.apTextPrimary)
                            .padding()
                            .background(Color.apSurface)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        APSectionHeader(title: "DOMÄN")
                        Picker("Domän", selection: $domain) {
                            ForEach(Domain.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(.apOrange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.apSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    let isDisabled = title.trimmingCharacters(in: .whitespaces).isEmpty
                    APPillButton(title: "Spara", action: {
                        let trimmed = title.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, domain)
                        dismiss()
                    })
                    .opacity(isDisabled ? 0.5 : 1)
                    .disabled(isDisabled)

                    APPillButton(title: "Avbryt", action: { dismiss() }, style: .secondary)
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Ny åtgärd")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .toolbarBackground(Color.apBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.medium])
    }
}
