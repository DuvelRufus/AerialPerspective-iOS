//
//  AssessmentView.swift
//  AerealPerspective
//
//  Created by Danny Axiotis on 2026-05-18.
//

import Foundation
import SwiftUI

struct AssessmentView: View {
    var assessment: Assessment
    var project: Project
    var questionStore: QuestionStore

    @State private var answerStore = AnswerStore()
    @State private var currentDomainIndex = 0

    var currentDomain: (domain: Domain, questions: [Question])? {
        guard currentDomainIndex < questionStore.groupedByDomain.count else { return nil }
        return questionStore.groupedByDomain[currentDomainIndex]
    }

    var domainScores: [DomainScore] {
        ScoringService.compute(
            answers: answerStore.answers,
            questions: questionStore.questions,
            options: questionStore.options
        )
    }

    var answeredCount: Int {
        questionStore.questions.filter { answerStore.answers[$0.id] != nil }.count
    }

    var totalCount: Int { questionStore.questions.count }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                progressBar

                if let group = currentDomain {
                    domainView(group: group)
                }
            }
        }
        .navigationTitle("Assessment \(assessment.version)")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { await answerStore.fetch(assessmentId: assessment.id) }
    }

    var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.white.opacity(0.1)
                Color.cyan
                    .frame(width: totalCount == 0 ? 0 : geo.size.width * CGFloat(answeredCount) / CGFloat(totalCount))
                    .animation(.easeInOut, value: answeredCount)
            }
        }
        .frame(height: 3)
    }

    func domainView(group: (domain: Domain, questions: [Question])) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text(group.domain.rawValue)
                    .font(.title.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 24)

                ForEach(group.questions) { question in
                    questionCard(question: question)
                }

                HStack {
                    if currentDomainIndex > 0 {
                        Button("Tillbaka") {
                            currentDomainIndex -= 1
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }

                    Spacer()

                    if currentDomainIndex < questionStore.groupedByDomain.count - 1 {
                        Button("Nästa") {
                            currentDomainIndex += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    } else {
                        NavigationLink("Klar") {
                            ResultView(
                                assessment: assessment,
                                project: project,
                                domainScores: domainScores,
                                answerStore: answerStore,
                                questionStore: questionStore
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                    }
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    func questionCard(question: Question) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(question.questionText)
                .foregroundStyle(.white)
                .font(.subheadline)

            ForEach(questionStore.optionsFor(question: question)) { option in
                Button {
                    Task {
                        await answerStore.save(
                            assessmentId: assessment.id,
                            questionId: question.id,
                            answerOptionId: option.id
                        )
                    }
                } label: {
                    HStack {
                        Text(option.label)
                            .foregroundStyle(.white)
                        Spacer()
                        if answerStore.answers[question.id] == option.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.cyan)
                        }
                    }
                    .padding()
                    .background(
                        answerStore.answers[question.id] == option.id
                            ? Color.cyan.opacity(0.2)
                            : Color.white.opacity(0.05)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
