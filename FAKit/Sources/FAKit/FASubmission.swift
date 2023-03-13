//
//  FASubmission.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages
import SwiftGraph
import OrderedCollections

public struct FASubmission: Equatable {
    public let url: URL
    public let previewImageUrl: URL
    public let fullResolutionImageUrl: URL
    public let widthOnHeightRatio: Float
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let htmlDescription: String
    public let isFavorite: Bool
    public let favoriteUrl: URL
    public let comments: [Comment]
    
    public init(url: URL, previewImageUrl: URL,
                fullResolutionImageUrl: URL,
                widthOnHeightRatio: Float, author: String,
                displayAuthor: String, authorAvatarUrl: URL,
                title: String, htmlDescription: String,
                isFavorite: Bool, favoriteUrl: URL,
                comments: [Comment]) {
        self.url = url
        self.previewImageUrl = previewImageUrl
        self.fullResolutionImageUrl = fullResolutionImageUrl
        self.widthOnHeightRatio = widthOnHeightRatio
        self.author = author
        self.displayAuthor = displayAuthor
        self.authorAvatarUrl = authorAvatarUrl
        self.title = title
        self.htmlDescription = htmlDescription.selfContainedFAHtml
        self.isFavorite = isFavorite
        self.favoriteUrl = favoriteUrl
        self.comments = comments
    }
    
    public struct Comment: Equatable {
        public let cid: Int
        public let displayAuthor: String
        public let authorAvatarUrl: URL
        public let datetime: String
        public let htmlMessage: String
        public let answers: [Comment]
        
        public init(cid: Int, displayAuthor: String, authorAvatarUrl: URL, datetime: String,
                    htmlMessage: String, answers: [FASubmission.Comment]) {
            self.cid = cid
            self.displayAuthor = displayAuthor
            self.authorAvatarUrl = authorAvatarUrl
            self.datetime = datetime
            self.htmlMessage = htmlMessage
            self.answers = answers
        }
    }
}

extension FASubmission.Comment {
    init(_ comment: FASubmissionPage.Comment) {
        self.init(cid: comment.cid,
                  displayAuthor: comment.displayAuthor,
                  authorAvatarUrl: comment.authorAvatarUrl,
                  datetime: comment.datetime,
                  htmlMessage: comment.htmlMessage.selfContainedFAHtmlComment,
                  answers: [])
    }
    
    func withAnswers(_ answers: [Self]) -> Self {
        Self.init(cid: cid,
                  displayAuthor: displayAuthor,
                  authorAvatarUrl: authorAvatarUrl,
                  datetime: datetime,
                  htmlMessage: htmlMessage,
                  answers: answers)
    }
}

extension FASubmission {
    static func childrenOf(comment: FASubmissionPage.Comment,
                           in graph: UnweightedGraph<Int>,
                           index: [Int: FASubmissionPage.Comment]) -> [Comment] {
        let children = graph.edgesForVertex(comment.cid)!
            .filter { $0.u == graph.indexOfVertex(comment.cid)! }
            .map { graph.vertexAtIndex($0.v) }
        
        return children
            .map { (Comment(index[$0]!), index[$0]!) }
            .map { comment, rawComment in
                comment.withAnswers(
                    childrenOf(comment: rawComment, in: graph, index: index)
                )
            }
    }
    
    static func buildCommentsTree(_ comments: [FASubmissionPage.Comment]) -> [Comment] {
        let commentsIndex = Dictionary(uniqueKeysWithValues: comments
            .map { ($0.cid, $0) })
        let graph = UnweightedGraph<Int>()
        var rootCommentIDs = [Int]()
        var lastCidAtIndentation = OrderedDictionary<Int, Int>()
        
        comments.forEach { _ = graph.addVertex($0.cid) }
        for comment in comments {
            lastCidAtIndentation[comment.indentation] = comment.cid
            lastCidAtIndentation.removeAll { (indentation: Int, cid: Int) in
                indentation > comment.indentation
            }
            
            if comment.indentation == 0 {
                rootCommentIDs.append(comment.cid)
            } else if let parentCid = lastCidAtIndentation.reversed().first(where: { (indentation: Int, cid: Int) in
                indentation < comment.indentation
            }) {
                graph.addEdge(from: parentCid.value, to: comment.cid, directed: true)
            } else {
                logger.error("\(String(describing: comment)) doesn't have any parent and is not a root")
                assertionFailure()
            }
        }
        
        return rootCommentIDs.map { cid in
            Comment(commentsIndex[cid]!)
                .withAnswers(childrenOf(comment: commentsIndex[cid]!,
                                        in: graph, index: commentsIndex))
        }
    }
    
    init(_ page: FASubmissionPage, url: URL) {
        self.init(url: url,
                  previewImageUrl: page.previewImageUrl,
                  fullResolutionImageUrl: page.fullResolutionImageUrl,
                  widthOnHeightRatio: page.widthOnHeightRatio,
                  author: page.author,
                  displayAuthor: page.displayAuthor,
                  authorAvatarUrl: page.authorAvatarUrl,
                  title: page.title,
                  htmlDescription: page.htmlDescription,
                  isFavorite: page.isFavorite,
                  favoriteUrl: page.favoriteUrl,
                  comments: Self.buildCommentsTree(page.comments))
    }
}
