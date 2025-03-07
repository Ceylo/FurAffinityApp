//
//  FAPageComment.swift
//  
//
//  Created by Ceylo on 16/04/2023.
//

import Foundation
import SwiftSoup

public enum FAPageComment: Equatable, Sendable {
    case visible(FAVisiblePageComment)
    case hidden(FAHiddenPageComment)
}

extension FAPageComment {
    public var cid: Int {
        switch self {
        case let .visible(comment):
            comment.cid
        case let .hidden(comment):
            comment.cid
        }
    }
    
    public var indentation: Int {
        switch self {
        case let .visible(comment):
            comment.indentation
        case let .hidden(comment):
            comment.indentation
        }
    }
    
    public var htmlMessage: String {
        switch self {
        case let .visible(comment):
            comment.htmlMessage
        case let .hidden(comment):
            comment.htmlMessage
        }
    }
}


public struct FAVisiblePageComment: Equatable, Sendable {
    public let cid: Int
    public let indentation: Int
    public let author: String
    public let displayAuthor: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
}

public struct FAHiddenPageComment: Equatable, Sendable {
    public let cid: Int
    public let indentation: Int
    public let htmlMessage: String
}

enum CommentType {
    case comment
    case shout
}

extension CommentType {
    struct DecodingConfig {
        let commentIdRegex: String
        let messageQuery: String
        let fallbackMessageQuery: String
    }
    
    var decodingDonfig: DecodingConfig {
        let defaultMessageQuery = "comment-container div.comment-content comment-user-text"
        switch self {
        case .comment:
            return DecodingConfig(
                commentIdRegex: "cid:(.+)",
                messageQuery: "comment-container div.comment-content comment-user-text div.user-submitted-links",
                fallbackMessageQuery: defaultMessageQuery
            )
        case .shout:
            return DecodingConfig(
                commentIdRegex: "shout-(.+)",
                messageQuery: defaultMessageQuery,
                fallbackMessageQuery: defaultMessageQuery
            )
        }
    }
}

extension FAPageComment {
    init?(_ node: SwiftSoup.Element, type: CommentType) throws {
        let config = type.decodingDonfig
        let rawCidString = try node.select("a").attr("id")
        let cid = try Int(rawCidString.substring(matching: config.commentIdRegex).unwrap()).unwrap()
        let widthStr = try node.attr("style").substring(matching: "width:(.+)%").unwrap()
        let indentation = try 100 - Int(widthStr).unwrap()
        let htmlMessage: String
        if let htmlMessageAttempt = try node.select(config.messageQuery).first() {
            htmlMessage = try htmlMessageAttempt.html()
        } else {
            htmlMessage = try node.select(config.fallbackMessageQuery).first()
                .unwrap().html()
        }
        
        do {
            let authorNode = try node.select("comment-container comment-username div.c-usernameBlock a.c-usernameBlock__displayName")
            let author = try authorNode
                .attr("href")
                .substring(matching: "/user/(.+)/")
                .unwrap()
            let displayAuthor = try authorNode.text()
            let datetimeNode = try node.select("comment-container div.comment-content comment-date span.popup_date")
            let naturalDatetime = try datetimeNode.text()
            let datetime = try datetimeNode.attr("title")
            
            self = .visible(.init(
                cid: cid, indentation: indentation,
                author: author, displayAuthor: displayAuthor,
                datetime: datetime, naturalDatetime: naturalDatetime,
                htmlMessage: htmlMessage
            ))
        } catch {
            logger.warning("\(error, privacy: .public)\nWhile parsing: \((try? node.html()) ?? "", privacy: .public)")
            self = .hidden(.init(cid: cid, indentation: indentation, htmlMessage: htmlMessage))
        }
    }
}
