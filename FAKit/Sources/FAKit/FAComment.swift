//
//  FAComment.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
import FAPages
import SwiftGraph
import OrderedCollections

public struct FAComment: Equatable {
    public let cid: Int
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
    public let answers: [FAComment]
    
    public init(cid: Int, author: String, displayAuthor: String, authorAvatarUrl: URL, datetime: String,
                naturalDatetime: String, htmlMessage: String, answers: [FAComment]) {
        self.cid = cid
        self.author = author
        self.displayAuthor = displayAuthor
        self.authorAvatarUrl = authorAvatarUrl
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.htmlMessage = htmlMessage
        self.answers = answers
    }
}

extension FAComment {
    init(_ comment: FAPageComment) {
        self.init(cid: comment.cid,
                  author: comment.author,
                  displayAuthor: comment.displayAuthor,
                  authorAvatarUrl: comment.authorAvatarUrl,
                  datetime: comment.datetime,
                  naturalDatetime: comment.naturalDatetime,
                  htmlMessage: comment.htmlMessage.selfContainedFAHtmlComment,
                  answers: [])
    }
    
    func withAnswers(_ answers: [Self]) -> Self {
        Self.init(cid: cid,
                  author: author,
                  displayAuthor: displayAuthor,
                  authorAvatarUrl: authorAvatarUrl,
                  datetime: datetime,
                  naturalDatetime: naturalDatetime,
                  htmlMessage: htmlMessage,
                  answers: answers)
    }
    
    static func childrenOf(comment: FAPageComment,
                           in graph: UnweightedGraph<Int>,
                           index: [Int: FAPageComment]) -> [FAComment] {
        let children = graph.edgesForVertex(comment.cid)!
            .filter { $0.u == graph.indexOfVertex(comment.cid)! }
            .map { graph.vertexAtIndex($0.v) }
        
        return children
            .map { (FAComment(index[$0]!), index[$0]!) }
            .map { comment, rawComment in
                comment.withAnswers(
                    childrenOf(comment: rawComment, in: graph, index: index)
                )
            }
    }
    
    static func buildCommentsTree(_ comments: [FAPageComment]) -> [FAComment] {
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
            FAComment(commentsIndex[cid]!)
                .withAnswers(childrenOf(comment: commentsIndex[cid]!,
                                        in: graph, index: commentsIndex))
        }
    }
}
