//
//  FACommentTests.swift
//
//
//  Created by Ceylo on 01/12/2022.
//

import Testing
@testable import FAKit
@testable import FAPages

extension FAPageComment {
    init(cid: Int, indentation: Int) {
        self = .visible(.init(
            cid: cid, indentation: indentation, author: "t", displayAuthor: "T",
            datetime: "Aug 12, 2022 04:08 AM", naturalDatetime: "Today", htmlMessage: "Msg"
        ))
    }
}

struct FACommentTests {
    @Test
    func buildCommentsTree_emptyListGivesEmptyTree() async throws {
        let tree = try await FAComment.buildCommentsTree([])
        #expect(tree == [])
    }

    @Test
    func buildCommentsTree_onlyRootsGivesFlatTree() async throws {
        let tree = try await FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 0),
            .init(cid: 166658565, indentation: 0),
        ])
        let expected = try await [
            FAComment(.init(cid: 166652793, indentation: 0)),
            FAComment(.init(cid: 166653891, indentation: 0)),
            FAComment(.init(cid: 166658565, indentation: 0)),
        ]
        #expect(tree == expected)
    }

    @Test
    func buildCommentsTree_simpleHierarchy() async throws {
        let tree = try await FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
        ])
        let expected = try await [
            FAComment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FAComment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658565, indentation: 6))
                ]),
            ]),
        ]
        #expect(tree == expected)
    }

    @Test
    func buildCommentsTree_complexHierarchy() async throws {
        let tree = try await FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
            .init(cid: 166663244, indentation: 3),
            .init(cid: 166652794, indentation: 3),
            .init(cid: 166658865, indentation: 6),
            .init(cid: 166656182, indentation: 0),
        ])
        let expected = try await [
            FAComment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FAComment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658565, indentation: 6))
                ]),
                FAComment(.init(cid: 166663244, indentation: 3)),
                FAComment(.init(cid: 166652794, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658865, indentation: 6))
                ]),
            ]),
            FAComment(.init(cid: 166656182, indentation: 0)),
        ]
        #expect(tree == expected)
    }

    @Test
    func recursiveCommentsCount() async throws {
        let tree = try await [
            FAComment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FAComment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658565, indentation: 6))
                ]),
                FAComment(.init(cid: 166663244, indentation: 3)),
                FAComment(.init(cid: 166652794, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658865, indentation: 6))
                ]),
            ]),
            FAComment(.init(cid: 166656182, indentation: 0)),
        ]
        #expect(tree.recursiveCount == 7)
    }
}
