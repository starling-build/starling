// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import OfficeApp

final class SitePublishResultTests: XCTestCase {
    func testAccessFailuresExplainAccountAndRepositoryWithoutEchoingCredentials() {
        for text in ["fatal: Authentication failed for 'https://person:secret@github.com/owner/repo'",
                     "fatal: could not read Username for 'https://github.com': terminal prompts disabled",
                     "git@github.com: Permission denied (publickey).", "remote: Repository not found.",
                     "fatal: unable to access URL: The requested URL returned error: 403"] {
            let issue = SitePublishIssue.upload(output: text)
            XCTAssertEqual(issue.kind, .authentication)
            XCTAssertTrue(issue.guidance.contains("repository address"))
            XCTAssertNotNil(issue.helpURL)
            XCTAssertFalse(issue.message.contains("secret"))
            XCTAssertTrue(issue.guidance.contains("still on this device"))
        }
    }

    func testRemoteChangesAreNotTreatedAsTransientFailure() {
        for text in ["! [rejected] HEAD -> main (fetch first)\nerror: failed to push some refs",
                     "! [rejected] HEAD -> main (non-fast-forward)",
                     "Updates were rejected because the remote contains work that you do not have locally"] {
            let issue = SitePublishIssue.upload(output: text)
            XCTAssertEqual(issue.kind, .remoteChanges)
            XCTAssertTrue(issue.guidance.contains("merge"))
            XCTAssertEqual(issue.retryTitle, "Publish after resolving changes")
            XCTAssertNil(issue.helpURL)
        }
    }

    func testConnectionFailuresDoNotClaimNothingWasUploaded() {
        for text in ["Could not resolve host: github.com", "Failed to connect to github.com",
                     "send-pack: unexpected disconnect while reading sideband packet",
                     "fatal: the remote end hung up unexpectedly", "Connection reset by peer",
                     "SSL certificate problem: certificate has expired"] {
            let issue = SitePublishIssue.upload(output: text)
            XCTAssertEqual(issue.kind, .connection)
            XCTAssertTrue(issue.guidance.contains("may have received"))
            XCTAssertFalse(issue.message.contains("Nothing was uploaded"))
        }
    }

    func testRejectionAndUnknownOutputStayActionableWithoutServerText() {
        let rejected = SitePublishIssue.upload(output: "remote: secret-token\n! [remote rejected] HEAD -> main (pre-receive hook declined)")
        XCTAssertEqual(rejected.kind, .rejected)
        XCTAssertTrue(rejected.guidance.contains("repository's rules"))
        XCTAssertFalse(rejected.message.contains("secret-token"))
        for text in ["", "localized failure secret-token", "fatal: unknown failure https://user:secret-token@host"] {
            let unknown = SitePublishIssue.upload(output: text)
            XCTAssertEqual(unknown.kind, .unconfirmed)
            XCTAssertFalse(unknown.message.contains("secret-token"))
            XCTAssertFalse(unknown.message.contains("Nothing was uploaded"))
        }
    }

    func testLocalFailureAndPostUploadBookkeepingHaveDifferentOutcomes() {
        let local = SitePublishResult("", .local("Could not build the website."))
        XCTAssertTrue(local.failure!.contains("Nothing was uploaded"))
        let sent = SitePublishResult("Built", .sent("The local receipt could not be saved."))
        XCTAssertEqual(sent.issue?.kind, .sent)
        XCTAssertTrue(sent.failure!.contains("upload succeeded"))
        XCTAssertFalse(sent.failure!.contains("Nothing was uploaded"))
        XCTAssertNil(SitePublishResult("Sent").failure)
    }
}
