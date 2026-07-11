//
//  HTMLView.swift
//  FurAffinity
//
//  Created by Ceylo on 02/01/2022.
//

import SwiftUI
import UIKit
import Kingfisher
import ImageIO
import UniformTypeIdentifiers
import Defaults

// Rendering HTML is a pain…
// - WKWebView embeds a UIScrollView and cannot size itself based on its contents
// - Text(attributedString) is unable to render some CSS/image attachments
// - UITextView autosizing is unable to wrap contents and will
// clip some contents if it cannot fit its ideal size.
//
// so we use UITextView with manual sizing, which unfortunately has to be asynchronous
//
// Animated GIFs (e.g. inline avatars) can't animate as text attachments: the HTML
// importer flattens them to a static frame, and TextKit 2's NSTextAttachmentViewProvider
// (which could host a live view) is never realized in a non-scrolling, self-sizing
// UITextView — it's only queried for bounds, so loadView() is never called. Instead we
// keep the static first frame as the attachment and overlay a live AnimatedImageView
// on top of each GIF, positioned from the text layout. Gated on `animateAvatars`.
struct HTMLView: View {
    var text: AttributedString
    @Default(.animateAvatars) var animateAvatars

    @State private var height: CGFloat

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.text = text
        self._height = State(initialValue: initialHeight)
    }

    var body: some View {
        GeometryReader { geometry in
            TextViewImpl(text: text,
                         animateGIFs: animateAvatars,
                         viewWidth: geometry.size.width,
                         neededHeight: $height)
        }
        .frame(height: height)
    }

    struct TextViewImpl: UIViewRepresentable {
        var text: AttributedString
        var animateGIFs: Bool
        var viewWidth: CGFloat
        @Binding var neededHeight: CGFloat

        func makeUIView(context: Context) -> GIFOverlayTextView {
            let view = GIFOverlayTextView()
            view.isEditable = false
            view.isScrollEnabled = false
            view.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
            view.setContent(NSAttributedString(text))
            view.animateGIFs = animateGIFs
            view.linkTextAttributes = [
                .underlineStyle : NSNumber(value: NSUnderlineStyle.single.union(.patternDot).union(.byWord).rawValue),
                .underlineColor : UIColor(white: 0.5, alpha: 0.8),
            ]
            view.backgroundColor = nil
            view.textContainerInset = .init(top: 3, left: 3, bottom: 3, right: 3)

            return view
        }

        func updateUIView(_ view: GIFOverlayTextView, context: Context) {
            let coordinator = context.coordinator
            if coordinator.appliedText != text {
                view.setContent(NSAttributedString(text))
                coordinator.appliedText = text
            }
            view.animateGIFs = animateGIFs

            let bounds = CGSize(width: viewWidth,
                                height: .greatestFiniteMagnitude)
            let fittingSize = view.systemLayoutSizeFitting(bounds)
            // Can't modify view during view update, hence async
            Task {
                neededHeight = fittingSize.height
            }
        }

        func makeCoordinator() -> Coordinator { Coordinator() }

        final class Coordinator {
            var appliedText: AttributedString?
        }
    }
}

/// A non-scrolling UITextView that keeps inline animated-GIF attachments as their
/// static first frame and overlays a live `Kingfisher.AnimatedImageView` on top of
/// each, positioned from the text layout. Repositioning happens in `layoutSubviews`
/// so the overlays follow the text on every width/height change.
final class GIFOverlayTextView: UITextView {
    private struct GIF {
        let range: NSRange
        let data: Data
        /// Baseline-relative layout bounds (`NSTextAttachment.bounds`).
        let bounds: CGRect
    }

    private var gifs: [GIF] = []
    private var overlays: [AnimatedImageView] = []

    var animateGIFs: Bool = true {
        didSet { if animateGIFs != oldValue { rebuildOverlays() } }
    }

    // Configure TextKit 2 through the designated `init(frame:textContainer:)` rather
    // than `UITextView(usingTextLayoutManager:)`: the latter is a factory initializer
    // that bypasses this subclass's Swift stored-property initialization (leaving
    // `gifs`/`overlays` as garbage → crash on first access).
    init() {
        let contentStorage = NSTextContentStorage()
        let layoutManager = NSTextLayoutManager()
        let container = NSTextContainer()
        layoutManager.textContainer = container
        contentStorage.addTextLayoutManager(layoutManager)
        super.init(frame: .zero, textContainer: container)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ attributedString: NSAttributedString) {
        attributedText = attributedString
        gifs = Self.findGIFs(in: attributedString)
        rebuildOverlays()
    }

    private func rebuildOverlays() {
        overlays.forEach { $0.removeFromSuperview() }
        overlays.removeAll()

        guard animateGIFs else { return }
        for gif in gifs {
            let imageView = AnimatedImageView()
            imageView.framePreloadCount = .max // matches FAAnimatedImage config
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.image = KingfisherWrapper<KFCrossPlatformImage>.image(
                data: gif.data,
                options: ImageCreatingOptions()
            )
            addSubview(imageView)
            overlays.append(imageView)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        positionOverlays()
    }

    private func positionOverlays() {
        guard !overlays.isEmpty,
              let layoutManager = textLayoutManager,
              let contentManager = layoutManager.textContentManager
        else { return }
        layoutManager.ensureLayout(for: layoutManager.documentRange)

        for (index, gif) in gifs.enumerated() where index < overlays.count {
            let overlay = overlays[index]
            if let segment = lineSegmentRect(for: gif.range,
                                             layoutManager: layoutManager,
                                             contentManager: contentManager) {
                overlay.isHidden = false
                // Match TextKit's static-attachment placement: bounds are baseline-relative
                // (y-up, origin on the baseline), so the top sits at
                // `baseline - bounds.origin.y - bounds.height`. Baseline-anchoring (vs.
                // centering on the line) keeps GIFs aligned with static neighbors.
                overlay.frame = CGRect(
                    x: segment.rect.minX,
                    y: segment.baselineY - gif.bounds.origin.y - gif.bounds.height,
                    width: gif.bounds.width,
                    height: gif.bounds.height
                )
            } else {
                overlay.isHidden = true
            }
        }
    }

    private struct LineSegment {
        /// Segment rect in this view's coordinate space (spans the full line height).
        let rect: CGRect
        /// Baseline Y in this view's coordinate space — TextKit's attachment datum.
        let baselineY: CGFloat
    }

    /// The line segment (in this view's coordinate space) enclosing the attachment
    /// at `nsRange`, or nil if it isn't laid out yet.
    private func lineSegmentRect(
        for nsRange: NSRange,
        layoutManager: NSTextLayoutManager,
        contentManager: NSTextContentManager
    ) -> LineSegment? {
        guard let start = contentManager.location(layoutManager.documentRange.location,
                                                  offsetBy: nsRange.location),
              let end = contentManager.location(start, offsetBy: nsRange.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }

        var segmentRect: CGRect?
        var segmentBaseline: CGFloat = 0
        layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, baselinePosition, _ in
            segmentRect = frame
            segmentBaseline = baselinePosition
            return false // first segment is enough for a single attachment
        }
        guard var rect = segmentRect else { return nil }
        // TextKit lays out in the container's coordinate space; the text is drawn
        // offset by textContainerInset (contentOffset is 0 for this non-scrolling view).
        rect.origin.x += textContainerInset.left
        rect.origin.y += textContainerInset.top
        // `baselinePosition` is relative to the segment frame's top edge.
        let baselineY = rect.minY + segmentBaseline
        return LineSegment(rect: rect, baselineY: baselineY)
    }

    private static func findGIFs(in attributedString: NSAttributedString) -> [GIF] {
        var result: [GIF] = []
        let fullRange = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttribute(.attachment, in: fullRange) { value, range, _ in
            guard let attachment = value as? NSTextAttachment,
                  let data = attachment.fileWrapper?.regularFileContents ?? attachment.contents,
                  isAnimatedGIF(data)
            else { return }
            result.append(GIF(range: range, data: data, bounds: attachment.bounds))
        }
        return result
    }

    private static func isAnimatedGIF(_ data: Data) -> Bool {
        // "GIF8" magic — cheap reject before decoding.
        guard data.starts(with: [0x47, 0x49, 0x46, 0x38]) else { return false }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        if let type = CGImageSourceGetType(source),
           UTType(type as String) != .gif {
            return false
        }
        return CGImageSourceGetCount(source) > 1
    }
}



#Preview {
    var html: String {
        "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n<html lang=\"en\" class=\"no-js\" xmlns=\"http://www.w3.org/1999/xhtml\">\n<head>\n<meta charset=\"utf-8\" />\n<meta name=\"viewport\"           content=\"width=device-width, initial-scale=1.0\" />\n<link type=\"text/css\" rel=\"stylesheet\" href=\"/themes/beta/css/ui_theme_dark.css\" /></head>\n<body data-static-path=\"/themes/beta\">"
        +
        "<code class=\"bbcode bbcode_center\"><strong class=\"bbcode bbcode_b\"> Happy New Year, guys! <br> Let the New Year bring happiness and joy to every home, because each of you deserves all the best!<br> Love you all!!! </strong></code>\n<br> \n<br> \n<br> \n<br> \n<br> \n<br> Rudy © \n<a href=\"/user/ruddi\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/ruddi.gif\" align=\"middle\" title=\"ruddi\" alt=\"ruddi\"></a>\n<br> Rigel Peyton © \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/lil-maj.gif\" align=\"middle\" title=\"lil-Maj\" alt=\"lil-Maj\"></a> \n<br> Annet © \n<a href=\"/user/annetpeas\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/annetpeas.gif\" align=\"middle\" title=\"annetpeas\" alt=\"annetpeas\"></a> \n<br> Seth © \n<a href=\"/user/longdanger\" class=\"iconusername\"><img src=\"https://a.furaffinity.net/20211231/longdanger.gif\" align=\"middle\" title=\"longdanger\" alt=\"longdanger\"></a>\n<br> \n<br> and Bulka © irl my pet cat \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        +
        "</body></html>"
    }
    
    var attributedString: AttributedString {
        let data = html
            .replacingOccurrences(of: "href=\"/", with: "href=\"https://www.furaffinity.net/")
            .replacingOccurrences(of: "src=\"//", with: "src=\"https://")
            .data(using: .utf8)!
        let nsattrstr = try! NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ],
            documentAttributes: nil)
        
        return AttributedString(nsattrstr)
    }
    
    ScrollView {
        HTMLView(text: attributedString)
            .border(.yellow)
    }
    .border(.blue)
    .preferredColorScheme(.dark)
}
