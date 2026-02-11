//
//  MesurementInputLayout.swift
//  DDiary
//
//  Created by Ilia Khokhlov on 22.12.25.
//

import SwiftUI

struct MeasurementInputLayout<Fields: View>: View {
    let title: String?
    @Binding var showCommentField: Bool
    @Binding var commentText: String
    let commentFieldAccessibilityId: String
    let addCommentAccessibilityId: String
    var isCommentFocused: FocusState<Bool>.Binding
    let commentFieldAnchorId: String
    let fields: Fields

    init(
        title: String? = nil,
        showCommentField: Binding<Bool>,
        commentText: Binding<String>,
        commentFieldAccessibilityId: String,
        addCommentAccessibilityId: String,
        isCommentFocused: FocusState<Bool>.Binding,
        commentFieldAnchorId: String,
        @ViewBuilder fields: () -> Fields
    ) {
        self.title = title
        self._showCommentField = showCommentField
        self._commentText = commentText
        self.commentFieldAccessibilityId = commentFieldAccessibilityId
        self.addCommentAccessibilityId = addCommentAccessibilityId
        self.isCommentFocused = isCommentFocused
        self.commentFieldAnchorId = commentFieldAnchorId
        self.fields = fields()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: DS.Spacing.medium) {
                    VStack(spacing: DS.Spacing.medium) {
                        if let title {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        fields
                    }
                    .padding(.top, DS.Spacing.large)
                    .padding(.horizontal)

                    VStack(alignment: .leading, spacing: DS.Spacing.small) {
                        if showCommentField {
                            VStack(alignment: .leading, spacing: DS.Spacing.s8) {
                                TextField(L10n.measurementCommentPlaceholder, text: $commentText, axis: .vertical)
                                    .autocorrectionDisabled(false)
                                    .textInputAutocapitalization(.sentences)
                                    .focused(isCommentFocused)
                                    .accessibilityIdentifier(commentFieldAccessibilityId)
                                    .padding(.vertical, 10)
                                Rectangle()
                                    .fill(InputCardStyle.strokeColor(isInvalid: false))
                                    .frame(height: 1)
                            }
                            .id(commentFieldAnchorId)
                        } else {
                            Button {
                                showCommentField = true
                                DispatchQueue.main.async { isCommentFocused.wrappedValue = true }
                            } label: {
                                HStack(spacing: DS.Spacing.s8) {
                                    Image(systemName: "plus.circle")
                                    Text(L10n.measurementAddComment)
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                            .accessibilityIdentifier(addCommentAccessibilityId)
                        }
                    }
                    .padding(.top, DS.Spacing.large)
                    .padding(.horizontal)
                }
                .padding(.bottom, DS.Spacing.large * 2)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: isCommentFocused.wrappedValue) { oldValue, newValue in
                if newValue {
                    withAnimation { proxy.scrollTo(commentFieldAnchorId, anchor: .center) }
                }
            }
        }
    }
}

private enum InputCardStyle {
    static var background: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color.secondary.opacity(0.1)
        #endif
    }

    static func strokeColor(isInvalid: Bool) -> Color {
        isInvalid ? .red : Color.secondary.opacity(0.25)
    }
}
