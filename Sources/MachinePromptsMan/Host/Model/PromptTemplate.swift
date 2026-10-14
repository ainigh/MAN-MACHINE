import Foundation

/// SPEC §9.1: fixed per spec version, short, the four verbs with one worked example, the projection,
/// and the output format. No chain-of-thought instructions. The version goes into every turn-log line.
public enum PromptTemplate {
    public static let version = "mpm-2.0/1"

    static let role = """
    You advise one person who works through a plan in timed rounds. You see the plan below as text. \
    Reply with one envelope and nothing else.
    """

    /// SPEC §9.1: the one extra sentence during a session.
    static let sessionSentence = """
    You are consulted between rounds and cannot change any timing. A commit is a patch that sets one \
    node doing and one node next.
    """

    static let verbs = """
    The envelope has exactly four keys:
    - say: what to tell the person, one to three short sentences. May be empty.
    - ask: one question that needs an answer, or null.
    - patch: proposed changes to the plan, a list of ops. The person accepts or rejects them. May be empty.
    - next: when you want to be consulted again, an ISO 8601 time, or null.

    Ops: add_node {tmp_id, parent, title}, update_node {id, fields}, move_node {id, parent}, cross_out {id}, \
    restore {id}, add_dep {id, dep}, remove_dep {id, dep}. Fields: title, status, due, progress, description, \
    links, ai_note, flags. Statuses: open, doing, next, done, crossed_out. Use the ids shown in brackets. \
    Never change a node marked [locked]. Use ai_note to remember something about a node.
    """

    static let example = """
    Example:
    ```envelope
    {"say":"Two cleared. Deploy next; the review can wait.","ask":null,"patch":[{"op":"update_node","id":"n_01J1","fields":{"status":"doing"}},{"op":"update_node","id":"n_01J0","fields":{"status":"next"}}],"next":null}
    ```
    """

    static let format = "Reply with a single ```envelope block containing the JSON."

    public static func render(projection: String, inSession: Bool, contextNote: String) -> String {
        var parts = [role]
        if inSession { parts.append(sessionSentence) }
        parts.append(verbs)
        parts.append(example)
        let note = contextNote.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { parts.append("About this person: \(note)") }
        parts.append(projection)
        parts.append(format)
        return parts.joined(separator: "\n\n")
    }

    /// SPEC §9.3 repair pass: one more chance to produce the envelope.
    public static func repair(raw: String) -> String {
        """
        Your previous reply could not be read. Rewrite it as a single ```envelope block containing JSON with \
        exactly the keys say, ask, patch and next. Nothing else.

        Previous reply:
        \(raw)
        """
    }
}
