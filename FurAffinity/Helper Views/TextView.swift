//
//  TextView.swift
//  FurAffinity
//
//  Created by Ceylo on 02/01/2022.
//

import SwiftUI

struct TextView: View {
    var text: AttributedString
    
    @State private var height: CGFloat
    
    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.text = text
        self._height = State(initialValue: initialHeight)
    }
    
    var body: some View {
        GeometryReader { geometry in
            TextViewImpl(text: text, viewWidth: geometry.size.width, neededHeight: $height)
        }
        .frame(height: height)
        .padding(.vertical, -5)
    }
    
    struct TextViewImpl: UIViewRepresentable {
        var text: AttributedString
        var viewWidth: CGFloat
        @Binding var neededHeight: CGFloat
        
        func makeUIView(context: Context) -> UITextView {
            let view = UITextView(usingTextLayoutManager: true)
            view.isEditable = false
            view.isScrollEnabled = false
            view.setContentCompressionResistancePriority(.fittingSizeLevel, for: .horizontal)
            view.attributedText = NSAttributedString(text)
            view.linkTextAttributes = [
                .underlineStyle : NSNumber(value: NSUnderlineStyle.single.union(.patternDot).union(.byWord).rawValue),
                .underlineColor : UIColor(white: 0.5, alpha: 0.8),
            ]
            view.backgroundColor = nil
            return view
        }
        
        func updateUIView(_ uiView: UITextView, context: Context) {
            let bounds = CGSize(width: viewWidth,
                                height: .greatestFiniteMagnitude)
            let fittingSize = uiView.systemLayoutSizeFitting(bounds)
            // Can't modify view during view update, hence async
            Task {
                neededHeight = fittingSize.height
            }
        }
    }
}



struct TextView_Previews: PreviewProvider {
    static var html: String {
        "<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\n<html lang=\"en\" class=\"no-js\" xmlns=\"http://www.w3.org/1999/xhtml\">\n<head>\n<meta charset=\"utf-8\" />\n<meta name=\"viewport\"           content=\"width=device-width, initial-scale=1.0\" />\n<link type=\"text/css\" rel=\"stylesheet\" href=\"/themes/beta/css/ui_theme_dark.css\" /></head>\n<body data-static-path=\"/themes/beta\">"
        +
        "<code class=\"bbcode bbcode_center\"><strong class=\"bbcode bbcode_b\"> Happy New Year, guys! <br> Let the New Year bring happiness and joy to every home, because each of you deserves all the best!<br> Love you all!!! </strong></code>\n<br> \n<br> \n<br> \n<br> \n<br> \n<br> Rudy © \n<a href=\"/user/ruddi\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/ruddi.gif\" align=\"middle\" title=\"ruddi\" alt=\"ruddi\"></a>\n<br> Rigel Peyton © \n<a href=\"/user/lil-maj\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/lil-maj.gif\" align=\"middle\" title=\"lil-Maj\" alt=\"lil-Maj\"></a> \n<br> Annet © \n<a href=\"/user/annetpeas\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211231/annetpeas.gif\" align=\"middle\" title=\"annetpeas\" alt=\"annetpeas\"></a> \n<br> Seth © \n<a href=\"/user/longdanger\" class=\"iconusername\"><img src=\"https://a.furaffinity.net/20211231/longdanger.gif\" align=\"middle\" title=\"longdanger\" alt=\"longdanger\"></a>\n<br> \n<br> and Bulka © irl my pet cat \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        +
        "</body></html>"
    }
    
    static var attributedString: AttributedString {
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
    
    static var previews: some View {
        ScrollView {
            TextView(text: attributedString)
                .border(.yellow)
        }
        .border(.blue)
        .preferredColorScheme(.dark)
    }
}
