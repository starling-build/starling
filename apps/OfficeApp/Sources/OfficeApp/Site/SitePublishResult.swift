// Copyright the Starling authors
// SPDX-License-Identifier: Apache-2.0

import Foundation

enum SitePublishStage {
    case checking, building, saving, uploading, recording
    var message: String {
        switch self {
        case .checking: return "Checking publishing setup…"
        case .building: return "Preparing the website and downloads…"
        case .saving: return "Saving publication history…"
        case .uploading: return "Uploading to hosting…"
        case .recording: return "Recording the successful upload…"
        }
    }
}

/// Recovery guidance is independent of Git's raw output, which can contain
/// credentials, server-provided text, or internal paths.
struct SitePublishIssue {
    enum Kind { case setup, local, authentication, connection, remoteChanges, rejected, unconfirmed, sent, cancelled, timedOut }
    let kind: Kind
    let title: String
    let guidance: String
    var message: String { title + " " + guidance }
    var retryTitle: String {
        switch kind {
        case .remoteChanges: return "Publish after resolving changes"
        case .sent: return "Publish"
        default: return "Try publishing again"
        }
    }
    var helpURL: String? {
        kind == .authentication ? "https://docs.github.com/en/get-started/git-basics/caching-your-github-credentials-in-git" : nil
    }

    static func setup(_ detail: String) -> Self {
        .init(kind: .setup, title: "Finish publishing setup.", guidance: detail + " Your saved writing is still on this device. Open Publishing settings to continue.")
    }
    static func local(_ detail: String) -> Self {
        .init(kind: .local, title: "The publication could not be prepared.", guidance: detail + " Nothing was uploaded. Your saved writing is still on this device.")
    }
    static func sent(_ detail: String) -> Self {
        .init(kind: .sent, title: "Sent to hosting; local setup needs attention.", guidance: detail + " The upload succeeded, but live deployment has not been verified.")
    }

    static let cancelled = Self(kind: .cancelled, title: "Upload stopped on this device.",
        guidance: "The remote result is unconfirmed: hosting may already have received data. Your saved writing and local history are still here. Try publishing again when you are ready.")
    static let timedOut = Self(kind: .timedOut, title: "The upload exceeded its time limit.",
        guidance: "Check your connection and hosting, then try publishing again. The remote result is unconfirmed: hosting may already have received data. Your saved writing and local history are still here.")

    /// Specific evidence wins over Git's generic trailing 'failed to push'.
    /// Unknown and connection failures do not prove the server rejected data.
    static func upload(output: String) -> Self {
        let text = output.lowercased()
        func contains(_ fragments: [String]) -> Bool { fragments.contains { text.contains($0) } }
        let saved = "Your saved writing and local publication history are still on this device."
        if contains(["non-fast-forward", "(fetch first)", "remote contains work that you do not have locally", "tip of your current branch is behind"]) {
            return .init(kind: .remoteChanges, title: "The online publication has other changes.",
                         guidance: "An update was rejected to protect the online history. Review and merge the remote changes in Git, then publish again. " + saved)
        }
        if contains(["authentication failed", "could not read username", "could not read password", "terminal prompts disabled", "permission denied (publickey)", "invalid username or token", "repository not found", "write access to repository not granted", "requested url returned error: 401", "requested url returned error: 403"]) {
            return .init(kind: .authentication, title: "Hosting access needs attention.",
                         guidance: "Check the repository address in Publishing settings, then sign in to an account with permission to upload. Use GitHub sign-in help if needed, then try publishing again. " + saved)
        }
        if contains(["could not resolve host", "could not resolve proxy", "could not resolve hostname", "failed to connect", "connection timed out", "connection reset", "connection refused", "network is unreachable", "remote end hung up", "unexpected disconnect", "ssl certificate problem", "unable to access"]) {
            return .init(kind: .connection, title: "The upload could not be confirmed.",
                         guidance: "Check your connection and try publishing again when hosting is reachable. The server may have received the upload before the connection failed. " + saved)
        }
        if contains(["[remote rejected]", "pre-receive hook declined", "protected branch", "gh006", "gh013", "file size limit", "exceeds github's file size limit"]) {
            return .init(kind: .rejected, title: "Hosting rejected this update.",
                         guidance: "Check the repository's rules, upload limits and publishing branch with its owner. Resolve the restriction before publishing again. " + saved)
        }
        return .init(kind: .unconfirmed, title: "The upload could not be confirmed.",
                     guidance: "Check hosting access and the repository's status, then try publishing again. Ask the repository owner to review the Git push if this keeps happening. " + saved)
    }
}

struct SitePublishResult {
    let summary: String
    let issue: SitePublishIssue?
    var failure: String? { issue?.message }
    init(_ summary: String, _ issue: SitePublishIssue? = nil) {
        self.summary = summary
        self.issue = issue
    }
}
