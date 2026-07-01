//
//  AssessmentView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import UIKit
import SwiftUI

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct GlowBurst: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 0.4

    var body: some View {
        Circle()
            .fill(Color.apOrange.opacity(opacity))
            .scaleEffect(scale)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    scale = 2.0
                    opacity = 0
                }
            }
    }
}

private struct GlowRing: View {
    @State private var scale: CGFloat = 1.0
    @State private var opacity: Double = 1.0

    var body: some View {
        RoundedRectangle(cornerRadius: 14)
            .stroke(Color.apOrange, lineWidth: 2)
            .scaleEffect(scale)
            .opacity(opacity)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 1.05
                    opacity = 0
                }
            }
    }
}

struct AssessmentView: View {
    var assessment: Assessment
    var project: Project
    var questionStore: QuestionStore

    @Environment(\.dismiss) private var dismiss

    @State private var answerStore = AnswerStore()
    @State private var currentQuestionIndex = 0
    @State private var isAdvancing = false
    @State private var navigatingForward = true
    @State private var glowOptionId: UUID? = nil
    @State private var showResult = false
    @State private var saveFailed = false

    var allQuestions: [Question] {
        questionStore.groupedByDomain.flatMap { $0.questions }
    }

    var currentQuestion: Question? {
        allQuestions[safe: currentQuestionIndex]
    }

    var currentDomainName: String {
        currentQuestion?.domain ?? ""
    }

    var domainScores: [DomainScore] {
        ScoringService.compute(
            answers: answerStore.answers,
            questions: questionStore.questions,
            options: questionStore.options
        )
    }

    var body: some View {
        ZStack {
            Color.apBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressSection

                if allQuestions.isEmpty {
                    Spacer()
                    ProgressView().tint(.apOrange)
                    Spacer()
                } else {
                    ZStack {
                        if let question = currentQuestion {
                            questionContent(question: question)
                                .id(currentQuestionIndex)
                                .transition(
                                    navigatingForward
                                    ? .asymmetric(
                                        insertion: .move(edge: .trailing),
                                        removal: .move(edge: .leading))
                                    : .asymmetric(
                                        insertion: .move(edge: .leading),
                                        removal: .move(edge: .trailing))
                                )
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .gesture(swipeGesture)
        .safeAreaInset(edge: .bottom) {
            if !allQuestions.isEmpty {
                let isLast = currentQuestionIndex >= allQuestions.count - 1
                let unanswered = allQuestions.filter { answerStore.answers[$0.id] == nil }.count
                let allAnswered = unanswered == 0
                VStack(spacing: 6) {
                    HStack(spacing: 12) {
                        APPillButton(title: "Föregående", action: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                navigatingForward = false
                                currentQuestionIndex -= 1
                            }
                        }, style: .secondary)
                        .disabled(currentQuestionIndex == 0)
                        .opacity(currentQuestionIndex == 0 ? 0.4 : 1)

                        if isLast {
                            APPillButton(title: "Se resultat", action: { showResult = true })
                                .disabled(!allAnswered)
                                .opacity(allAnswered ? 1 : 0.5)
                        } else {
                            APPillButton(title: "Nästa", action: {
                                guard !isAdvancing else { return }
                                isAdvancing = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    navigatingForward = true
                                    currentQuestionIndex = min(currentQuestionIndex + 1, allQuestions.count - 1)
                                } completion: {
                                    isAdvancing = false
                                }
                            })
                            .disabled(isAdvancing)
                        }
                    }

                    if isLast && !allAnswered {
                        Text(unanswered == 1 ? "1 fråga kvar" : "\(unanswered) frågor kvar")
                            .font(.caption)
                            .foregroundStyle(.apTextTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.apBackground)
            }
        }
        .navigationTitle("Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(isPresented: $showResult) {
            ResultView(
                assessment: assessment,
                project: project,
                domainScores: domainScores,
                answerStore: answerStore,
                questionStore: questionStore,
                onDone: { dismiss() }
            )
        }
        .task {
            await answerStore.fetch(assessmentId: assessment.id)
            currentQuestionIndex = findStartingIndex()
        }
        .onChange(of: currentQuestionIndex) { _, _ in
            // Safety net: if the index lands out of range, snap to the last
            // question rather than rendering a blank screen via [safe:].
            if currentQuestion == nil && !allQuestions.isEmpty {
                currentQuestionIndex = allQuestions.count - 1
            }
        }
        .onChange(of: currentQuestionIndex) { _, _ in
            saveFailed = false
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.apHairline)
                    Capsule()
                        .fill(Color.apOrange)
                        .frame(
                            width: allQuestions.isEmpty ? 0 :
                                geo.size.width * CGFloat(currentQuestionIndex + 1) / CGFloat(allQuestions.count)
                        )
                        .animation(.spring(), value: currentQuestionIndex)
                }
            }
            .frame(height: 4)
            .padding(.horizontal, 16)

            Text("Fråga \(currentQuestionIndex + 1) av \(max(allQuestions.count, 1))")
                .font(.caption)
                .foregroundStyle(.apTextTertiary)
        }
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Question content

    private func questionContent(question: Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Domain badge
                Text(currentDomainName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.apOrange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.apOrangeTint)
                    .clipShape(Capsule())
                    .id(currentDomainName)
                    .transition(.scale.combined(with: .opacity))

                // Question card with options
                APCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(question.questionText)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.apTextPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let tip = question.tooltip, !tip.isEmpty {
                            Text(tip)
                                .font(.caption)
                                .foregroundStyle(.apTextSecondary)
                        }

                        VStack(spacing: 10) {
                            ForEach(questionStore.optionsFor(question: question)) { option in
                                optionButton(option: option, question: question)
                            }
                        }
                    }
                }

                if saveFailed {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                        Text("Svaret kunde inte sparas. Försök igen.")
                            .font(.caption)
                    }
                    .foregroundStyle(.apRisk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.apRisk.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Option button

    @ViewBuilder
    private func optionButton(option: AnswerOption, question: Question) -> some View {
        let isSelected = answerStore.answers[question.id] == option.id
        let shape = RoundedRectangle(cornerRadius: 14)
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task { await selectOption(option: option, question: question) }
        } label: {
            HStack(spacing: 10) {
                Text(option.label)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.white : Color.apTextPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                        .transition(.scale(scale: 0).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background {
                if isSelected {
                    shape.fill(LinearGradient.apOrangeGradient)
                } else {
                    shape.fill(Color.apSurfaceElevated)
                        .overlay(shape.strokeBorder(Color.apHairline, lineWidth: 1))
                }
            }
            .shadow(color: isSelected ? Color.apOrange.opacity(0.4) : .clear, radius: 8)
            .overlay {
                if glowOptionId == option.id {
                    GlowBurst().clipShape(shape)
                }
            }
            .clipShape(shape)
            .overlay {
                if glowOptionId == option.id {
                    GlowRing()
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
    }

    // MARK: - Actions

    private func selectOption(option: AnswerOption, question: Question) async {
        withAnimation(.easeInOut(duration: 0.2)) {
            saveFailed = false
        }
        await answerStore.save(
            assessmentId: assessment.id,
            questionId: question.id,
            answerOptionId: option.id
        )
        // save() är icke-kastande: lyckad = inget store-fel, eller att det
        // optimistiska valet står kvar (per fråga — robust mot ett kvarhängande
        // fel från en samtidig save på en annan fråga).
        let saved = answerStore.error == nil || answerStore.answers[question.id] == option.id
        guard saved else {
            if currentQuestion?.id == question.id {
                withAnimation(.easeInOut(duration: 0.2)) {
                    saveFailed = true
                }
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            return
        }
        glowOptionId = option.id
        let isLast = currentQuestionIndex >= allQuestions.count - 1
        Task {
            try? await Task.sleep(for: .seconds(0.3))
            glowOptionId = nil
        }
        if !isLast {
            guard !isAdvancing else { return }
            isAdvancing = true
            Task {
                try? await Task.sleep(for: .seconds(0.15))
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    navigatingForward = true
                    currentQuestionIndex = min(currentQuestionIndex + 1, allQuestions.count - 1)
                } completion: {
                    isAdvancing = false
                }
            }
        }
    }

    private func findStartingIndex() -> Int {
        guard !allQuestions.isEmpty else { return 0 }
        let firstUnanswered = allQuestions.firstIndex { answerStore.answers[$0.id] == nil }
        return firstUnanswered ?? allQuestions.count - 1
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
                guard isHorizontal else { return }
                if value.translation.width < -40, currentQuestionIndex < allQuestions.count - 1 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        navigatingForward = true
                        currentQuestionIndex += 1
                    }
                } else if value.translation.width > 40, currentQuestionIndex > 0 {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        navigatingForward = false
                        currentQuestionIndex -= 1
                    }
                }
            }
    }
}
