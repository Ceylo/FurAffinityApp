//
//  FASubmissionTests.swift
//  
//
//  Created by Ceylo on 01/12/2022.
//

import XCTest
@testable import FAKit
@testable import FAPages

extension FASubmissionPage.Comment {
    init(cid: Int, indentation: Int) {
        self.init(
            cid: cid, indentation: indentation, author: "t", displayAuthor: "T",
            authorAvatarUrl: URL(string: "https://some.url/")!, datetime: "Aug 12, 2022 04:08 AM", naturalDatetime: "Today", htmlMessage: "Msg"
        )
    }
}

class FASubmissionTests: XCTestCase {
    func testBuildCommentsTree_emptyListGivesEmptyTree() {
        let tree = FASubmission.buildCommentsTree([])
        XCTAssertEqual(tree, [])
    }
    
    func testBuildCommentsTree_onlyRootsGivesFlatTree() {
        let tree = FASubmission.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 0),
            .init(cid: 166658565, indentation: 0),
        ])
        XCTAssertEqual(tree, [
            FASubmission.Comment(.init(cid: 166652793, indentation: 0)),
            FASubmission.Comment(.init(cid: 166653891, indentation: 0)),
            FASubmission.Comment(.init(cid: 166658565, indentation: 0)),
        ])
    }
    func testBuildCommentsTree_simpleHierarchy() {
        let tree = FASubmission.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
        ])
        XCTAssertEqual(tree, [
            FASubmission.Comment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FASubmission.Comment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FASubmission.Comment(.init(cid: 166658565, indentation: 6))
                ]),
            ]),
        ])
    }
    
    func testBuildCommentsTree_complexHierarchy() {
        let tree = FASubmission.buildCommentsTree([
            .init(cid: 166652793, indentation: 0),
            .init(cid: 166653891, indentation: 3),
            .init(cid: 166658565, indentation: 6),
            .init(cid: 166663244, indentation: 3),
            .init(cid: 166652794, indentation: 3),
            .init(cid: 166658865, indentation: 6),
            .init(cid: 166656182, indentation: 0),
        ])
        XCTAssertEqual(tree, [
            FASubmission.Comment(.init(cid: 166652793, indentation: 0)).withAnswers([
                FASubmission.Comment(.init(cid: 166653891, indentation: 3)).withAnswers([
                    FASubmission.Comment(.init(cid: 166658565, indentation: 6))
                ]),
                FASubmission.Comment(.init(cid: 166663244, indentation: 3)),
                FASubmission.Comment(.init(cid: 166652794, indentation: 3)).withAnswers([
                    FASubmission.Comment(.init(cid: 166658865, indentation: 6))
                ]),
            ]),
            FASubmission.Comment(.init(cid: 166656182, indentation: 0)),
        ])
    }
}
