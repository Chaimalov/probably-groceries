import Foundation

struct ClarificationNotice: Equatable {
    enum Kind: String { case question, answer }
    let itemID: UUID
    let listID: UUID
    let kind: Kind
    let text: String

    static func changes(from before: ShoppingData, to after: ShoppingData,
                        sharedListIDs: Set<UUID>) -> [ClarificationNotice] {
        // A first import is history, not a burst of new partner messages.
        let knownLists = Set(before.lists.map(\.id)).intersection(sharedListIDs)
        let previous = Dictionary(uniqueKeysWithValues: before.items.map { ($0.id, $0) })
        return after.items.compactMap { item in
            guard knownLists.contains(item.listID), let current = item.clarification,
                  !current.resolved else { return nil }
            let old = previous[item.id]?.clarification
            guard current != old else { return nil }
            if let answer = current.answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               answer != old?.answer || current.question != old?.question {
                return Self(itemID: item.id, listID: item.listID, kind: .answer, text: answer)
            }
            if current.question != old?.question && !current.question.isEmpty {
                return Self(itemID: item.id, listID: item.listID, kind: .question, text: current.question)
            }
            return nil
        }
    }
}

enum ClarificationReadState {
    private static func token(_ value: ItemClarification?) -> String? {
        guard let value, let answer = value.answer, !answer.isEmpty, !value.resolved else { return nil }
        return Data((value.question + "\0" + answer).utf8).base64EncodedString()
    }

    static func hasUnreadReply(_ item: ShoppingItem, receipts: String) -> Bool {
        guard let token = token(item.clarification) else { return false }
        return decode(receipts)[item.id.uuidString] != token
    }

    static func markingRead(_ item: ShoppingItem, receipts: String) -> String {
        guard let token = token(item.clarification) else { return receipts }
        var values = decode(receipts)
        values[item.id.uuidString] = token
        guard let data = try? JSONEncoder().encode(values) else { return receipts }
        return String(data: data, encoding: .utf8) ?? receipts
    }

    private static func decode(_ value: String) -> [String: String] {
        value.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }
}
