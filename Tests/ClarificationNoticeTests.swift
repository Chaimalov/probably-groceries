import XCTest

final class ClarificationNoticeTests: XCTestCase {
    private func fixture() -> ShoppingData {
        let product = Product(id: UUID(), name: "חלב", usualQuantity: 1)
        let item = ShoppingItem(id: UUID(), productID: product.id, quantity: 1, addedAt: .now)
        return ShoppingData(products: [product], items: [item])
    }

    func testQuestionAndAnswerAreScopedAndRevisionReplayIsSilent() {
        let before = fixture()
        var question = before
        question.items[0].clarification = ItemClarification(question: "איזה סוג?")
        let lists: Set<UUID> = [ShoppingList.defaultID]
        XCTAssertEqual(ClarificationNotice.changes(from: before, to: question, sharedListIDs: lists).first?.kind, .question)
        XCTAssertEqual(ClarificationNotice.changes(from: ShoppingData(lists: before.lists), to: question,
            sharedListIDs: lists).first?.kind, .question)
        XCTAssertTrue(ClarificationNotice.changes(from: question, to: question, sharedListIDs: lists).isEmpty)
        XCTAssertTrue(ClarificationNotice.changes(from: before, to: question, sharedListIDs: []).isEmpty)
        var reply = question
        reply.items[0].clarification?.answer = "הרגיל"
        XCTAssertEqual(ClarificationNotice.changes(from: question, to: reply, sharedListIDs: lists).first?.kind, .answer)
        var resolved = reply
        resolved.items[0].clarification?.resolved = true
        XCTAssertTrue(ClarificationNotice.changes(from: reply, to: resolved, sharedListIDs: lists).isEmpty)
    }

    func testFirstSharedImportDoesNotNotifyHistoricalQuestions() {
        var imported = fixture()
        let listID = UUID()
        imported.lists = [ShoppingList(id: listID, name: "משותפת")]
        imported.items[0].listID = listID
        imported.items[0].clarification = ItemClarification(question: "ישן")
        XCTAssertTrue(ClarificationNotice.changes(from: ShoppingData(), to: imported, sharedListIDs: [listID]).isEmpty)
    }

    func testReadingReplyIsLocalAndChangedReplyBecomesUnreadAgain() {
        var data = fixture()
        data.items[0].clarification = ItemClarification(question: "איזה סוג?", answer: "הרגיל")
        let row = data.items[0]
        XCTAssertTrue(ClarificationReadState.hasUnreadReply(row, receipts: "{}"))
        let receipts = ClarificationReadState.markingRead(row, receipts: "{}")
        XCTAssertFalse(ClarificationReadState.hasUnreadReply(row, receipts: receipts))
        var changed = row
        changed.clarification?.answer = "בעצם ללא סוכר"
        XCTAssertTrue(ClarificationReadState.hasUnreadReply(changed, receipts: receipts))
        XCTAssertEqual(row.clarification?.answer, "הרגיל")
    }
}
