//
//  SubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import URLImage
import FAKit
import Foundation
import Zoomable

extension FASubmission.Theme {
    init(style: UIUserInterfaceStyle) {
        switch style {
        case .unspecified, .dark:
            self = .dark
        case .light:
            self = .light
        @unknown default:
            self = .dark
        }
    }
}

extension FASubmission {
    var attributedDescription: AttributedString? {
        let theme = FASubmission.Theme(style: UITraitCollection.current.userInterfaceStyle)
        guard let data = htmlDescription(theme: theme).data(using: .utf8),
              let nsattrstr = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
                ],
                documentAttributes: nil)
        else { return nil }
        
        return AttributedString(nsattrstr)
            .transformingAttributes(\.foregroundColor) { foregroundColor in
                if foregroundColor.value == nil {
                    foregroundColor.value = .primary
                }
            }
            .transformingAttributes(\.font) { font in
                font.value = .body
            }
    }
}

struct SubmissionView: View {
    @EnvironmentObject var model: Model
    
    var preview: FASubmissionPreview
    var submissionProvider: () async -> FASubmission?
    var buttonsSize: CGFloat = 55
    @State private var avatarUrl: URL?
    @State private var submission: FASubmission?
    @State private var fullResolutionCGImage: CGImage?
    @State private var description: AttributedString?
    @State private var showZoomableSheet = false
    
    func header(submission: FASubmissionPreview) -> some View {
        SubmissionHeaderView(author: submission.displayAuthor,
                             title: submission.title,
                             avatarUrl: avatarUrl)
            .task {
                avatarUrl = await model.session?.avatarUrl(for: submission.author)
            }
    }
    
    func mainImage(submission: FASubmission) -> some View {
        URLImage(submission.fullResolutionImageUrl) { progress in
            Centered {
                CircularProgress(progress: CGFloat(progress ?? 0))
                    .frame(width: 100, height: 100)
            }
            .aspectRatio(CGFloat(preview.thumbnailWidthOnHeightRatio),
                         contentMode: .fit)
        } failure: { error, retry in
            Centered {
                Text("Oops, image loading failed 😞")
                Text(error.localizedDescription)
                    .font(.caption)
            }
        } content: { image, info in
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .transition(.opacity.animation(.default.speed(2)))
                .onAppear {
                    fullResolutionCGImage = info.cgImage
                }
                .sheet(isPresented: $showZoomableSheet) {
                    Zoomable(allowZoomOutBeyondFit: false) {
                        image
                    }
                    .ignoresSafeArea()
                }
                .onTapGesture {
                    showZoomableSheet = true
                }
        }
        .cornerRadius(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            if let submission = submission {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        header(submission: preview)
                        mainImage(submission: submission)
                        
                        SubmissionControlsView(submissionUrl: submission.url, fullResolutionImage: fullResolutionCGImage, likeAction: nil)
                        
                        if let description = description {
                            TextView(text: description)
                        }
                    }
                    .padding(10)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            submission = await submissionProvider()
            description = submission?.attributedDescription
        }
    }
}

extension SubmissionView {
    init(_ model: Model, preview: FASubmissionPreview) {
        self.init(preview: preview) {
            await model.session?.submission(for: preview)
        }
    }
}

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionView(preview: OfflineFASession.default.submissionPreviews[0],
                       submissionProvider: { FASubmission.demo })
            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
