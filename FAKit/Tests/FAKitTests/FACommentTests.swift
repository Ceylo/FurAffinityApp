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
    func buildCommentsTree_orphanedCommentThrows() async throws {
        // Comment 166653891 has indentation 3 but appears before any root comment,
        // so there is no preceding comment with lower indentation. It is an orphan
        // and should signal an error rather than silently promoting to root.
        await #expect(throws: FACommentError.orphanedComment(cid: 166653891)) {
            try await FAComment.buildCommentsTree([
                .init(cid: 166653891, indentation: 3),
                .init(cid: 166652793, indentation: 0),
            ])
        }
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

    @Test
    func recursivePath() async throws {
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

        // Leaf: full chain from its top-level ancestor.
        #expect(tree.recursivePath(toCid: 166658565)?.map(\.cid)
                == [166652793, 166653891, 166658565])
        // Mid-level node.
        #expect(tree.recursivePath(toCid: 166652794)?.map(\.cid)
                == [166652793, 166652794])
        // Top-level root: just itself.
        #expect(tree.recursivePath(toCid: 166656182)?.map(\.cid) == [166656182])
        // Missing cid.
        #expect(tree.recursivePath(toCid: 999) == nil)
    }
}
