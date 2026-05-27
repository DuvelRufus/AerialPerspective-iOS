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

struct AssessmentView: View {
    var assessment: Assessment
    var project: Project
    var questionStore: QuestionStore

    @State private var answerStore = AnswerStore()
    @State private var currentQuestionIndex = 0
    @State private var navigatingForward = true
    @State private var glowOptionId: UUID? = nil
    @State private var showResult = false

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
        .navigationTitle("Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .toolbarBackground(Color.apBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(currentQuestionIndex > 0)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if currentQuestionIndex > 0 {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            navigatingForward = false
                            currentQuestionIndex -= 1
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Tillbaka")
                        }
                        .foregroundStyle(.apOrange)
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showResult) {
            ResultView(
                assessment: assessment,
                project: project,
                domainScores: domainScores,
                answerStore: answerStore,
                questionStore: questionStore
            )
        }
        .task {
            await answerStore.fetch(assessmentId: assessment.id)
            currentQuestionIndex = findStartingIndex()
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.apOrange)
                        .frame(
                            width: allQuestions.isEmpty ? 0 :
                                geo.size.width * CGFloat(currentQuestionIndex) / CGFloat(allQuestions.count)
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

                        VStack(spacing: 8) {
                            ForEach(questionStore.optionsFor(question: question)) { option in
                                optionButton(option: option, question: question)
                            }
                        }
                    }
                }

                // Se resultat after final question is answered
                if currentQuestionIndex == allQuestions.count - 1,
                   answerStore.answers[question.id] != nil {
                    APPillButton(title: "Se resultat") {
                        showResult = true
                    }
                    .padding(.top, 4)
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
        Button {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            Task { await selectOption(option: option, question: question) }
        } label: {
            Text(option.label)
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.white : Color.apTextPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background {
                    if isSelected {
                        Capsule().fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color(hex: "#FF8C42"), location: 0),
                                    .init(color: Color(hex: "#F97316"), location: 0.5),
                                    .init(color: Color(hex: "#C2410C"), location: 1),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    } else {
                        Capsule().fill(Color.apSurfaceElevated)
                    }
                }
                .overlay {
                    if glowOptionId == option.id {
                        GlowBurst()
                            .clipShape(Capsule())
                    }
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Actions

    private func selectOption(option: AnswerOption, question: Question) async {
        await answerStore.save(
            assessmentId: assessment.id,
            questionId: question.id,
            answerOptionId: option.id
        )
        glowOptionId = option.id
        let isLast = currentQuestionIndex >= allQuestions.count - 1
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            glowOptionId = nil
            if !isLast {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    navigatingForward = true
                    currentQuestionIndex += 1
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
