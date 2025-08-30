//
//  FANotesPage.swift
//  
//
//  Created by Ceylo on 07/04/2022.
//

import Foundation
@preconcurrency import SwiftSoup

public struct FANotesPage: Equatable, Sendable {
    public struct NoteHeader: Equatable, Sendable {
        public let id: Int
        public let author: String
        public let displayAuthor: String
        public let title: String
        public let datetime: String
        public let naturalDatetime: String
        public let unread: Bool
        public let noteUrl: URL
    }
    
    public let noteHeaders: [NoteHeader?]
}

extension FANotesPage {
    private static let notesQuery = createEvaluator("div.c-noteListItem div.note-list-container")
    
    public init?(data: Data) {
        let state = signposter.beginInterval("All Notes Preview Parsing")
        defer { signposter.endInterval("All Notes Preview Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            
            // Get the parent node containing the list of notes by ID, which is speeds up finding the
            // the individual notes.
            guard let notesList = try doc.getElementById("notes-list") else {
                return nil
            }
            
            let noteNodes = try CssSelector.select(Self.notesQuery, notesList)
            self.noteHeaders = try noteNodes.map { try NoteHeader($0) }
        } catch {
            logger.error("Decoding failure in \(#file, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
}

extension FANotesPage.NoteHeader {
    private static let baseQuery = createEvaluator("div.note-list-subjectgroup div.note-list-subject-container a.notelink")
    private static let inputQuery = createEvaluator("div.note-list-subjectgroup div.note-list-checkbox input")
    private static let titleQuery = createEvaluator("div.c-noteListItem__subject")
    private static let authorQuery = createEvaluator("div.note-list-sendgroup div.note-list-sender-container div.note-list-sender div a.c-usernameBlock__displayName")
    private static let deletedUserQuery = createEvaluator("div.note-list-sendgroup div.note-list-sender-container div.note-list-sender div span.user-name-deleted")
    private static let datetimeQuery = createEvaluator("div.note-list-sendgroup div.note-list-senddate span.popup_date")
    
    init(_ node: SwiftSoup.Element) throws {
        let state = signposter.beginInterval("Note Preview Parsing")
        defer { signposter.endInterval("Note Preview Parsing", state) }
        
        let baseNode = try CssSelector.select(Self.baseQuery, node)
        let unread = baseNode.hasClass("note-unread")
        let noteUrlStr = try baseNode.attr("href")
        let noteUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + noteUrlStr)
        
        let idStr = try CssSelector.select(Self.inputQuery, node).attr("value")
        guard let id = Int(idStr) else { throw FAPagesError.parserFailureError() }
        let noteTitle = try elementsSelect(Self.titleQuery, baseNode.array()).text()
        
        let authorNode = try CssSelector.select(Self.authorQuery, node)
        var author: String
        let displayAuthor: String
        do {
            author = try authorNode.attr("href")
                .substring(matching: "/user/(.+)/")
                .unwrap()
            displayAuthor = try authorNode.text()
        } catch {
            let result = try CssSelector.select(Self.deletedUserQuery, node)
                .text(trimAndNormaliseWhitespace: true)
            guard result == "[deleted]" else {
                throw FAPagesError.parserFailureError()
            }
            author = ""
            displayAuthor = "[deleted user]"
        }
        
        let datetimeNode = try CssSelector.select(Self.datetimeQuery, node)
        let datetime = try datetimeNode.attr("title")
        let naturalDatetime = try datetimeNode.text()
        
        self.init(id: id, author: author, displayAuthor: displayAuthor, title: noteTitle, datetime: datetime, naturalDatetime: naturalDatetime, unread: unread, noteUrl: noteUrl)
    }
}

/// Helper function to create an evaluator from a query string. Since all queries are static they must never throw an error.
private func createEvaluator(_ query: String) -> Evaluator {
    do {
        return try QueryParser.parse(query)
    } catch {
        fatalError("Cannot evaluate query '\(query)': \(error)")
    }
}

/// Helper function to query on an `Elements` instance.
/// Once SwiftSoup > 2.10.3 is out, this function can be removed since `baseNode.select(Self.titleQuery)` will be supported.
private func elementsSelect(_ evaluator: Evaluator, _ roots: Array<Element>)throws->Elements {
    var elements: Array<Element> = Array<Element>()
    var seenElements: Array<Element> = Array<Element>()
    // dedupe elements by identity, not equality

    for root: Element in roots {
        let found: Elements = try CssSelector.select(evaluator, root)
        for  el: Element in found.array() {
            if (!seenElements.contains(el)) {
                elements.append(el)
                seenElements.append(el)
            }
        }
    }
    return Elements(elements)
}
