//
//  FACommentTests.swift
//  
//
//  Created by Ceylo on 01/12/2022.
//

import XCTest
@testable import FAKit
@testable import FAPages

extension FAPageComment {
    init(cid: Int, indentation: Int) {
        self = .visible(.init(
            cid: cid, indentation: indentation, author: "t", displayAuthor: "T",
            authorAvatarUrl: URL(string: "https://some.url/")!, datetime: "Aug 12, 2022 04:08 AM", naturalDatetime: "Today", htmlMessage: "Msg"
        ))
    }
}

class FACommentTests: XCTestCase {
    func testBuildCommentsTree_emptyListGivesEmptyTree() {
        let tree = FAComment.buildCommentsTree([])
        XCTAssertEqual(tree, [])
    }
    
    func testBuildCommentsTree_onlyRootsGivesFlatTree() {
        let tree = FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 0),
            .init(cid: 166658565, indentation: 0),
        ])
        XCTAssertEqual(tree, [
            FAComment(.init(cid: 166652793, indentation: 0)),
            FAComment(.init(cid: 166653891, indentation: 0)),
            FAComment(.init(cid: 166658565, indentation: 0)),
        ])
    }
    func testBuildCommentsTree_simpleHierarchy() {
        let tree = FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
        ])
        XCTAssertEqual(tree, [
            FAComment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FAComment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FAComment(.init(cid: 166658565, indentation: 6))
                ]),
            ]),
        ])
    }
    
    func testBuildCommentsTree_complexHierarchy() {
        let tree = FAComment.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
            .init(cid: 166663244, indentation: 3),
            .init(cid: 166652794, indentation: 3),
            .init(cid: 166658865, indentation: 6),
            .init(cid: 166656182, indentation: 0),
        ])
        XCTAssertEqual(tree, [
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
        ])
    }
}
