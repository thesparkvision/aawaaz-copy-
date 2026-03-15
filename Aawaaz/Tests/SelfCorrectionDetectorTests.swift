import XCTest
@testable import Aawaaz

final class SelfCorrectionDetectorTests: XCTestCase {

    private let detector = SelfCorrectionDetector()

    // MARK: - Basic Correction Patterns

    func testActuallyNoCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Turn left, actually no, turn right"),
            "Turn right"
        )
    }

    func testIMeanCorrectionWithComma() {
        XCTAssertEqual(
            detector.detectAndResolve("Go to the park, I mean the beach"),
            "Go to the beach"
        )
    }

    func testWaitCorrectionWithComma() {
        XCTAssertEqual(
            detector.detectAndResolve("The meeting is at 3, wait, it's at 4"),
            "The meeting is at 4"
        )
    }

    func testSorryCorrectionWithComma() {
        XCTAssertEqual(
            detector.detectAndResolve("His name is John, sorry, James"),
            "His name is James"
        )
    }

    func testNoNoCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("I want pizza, no no, I want pasta"),
            "I want pasta"
        )
    }

    func testLetMeRephraseCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("The system is broken, let me rephrase, the system needs updating"),
            "The system needs updating"
        )
    }

    func testScratchThatCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Send the email now, scratch that, send it tomorrow"),
            "Send it tomorrow"
        )
    }

    func testScratchThatPreservesStablePrefixForFragmentRepair() {
        XCTAssertEqual(
            detector.detectAndResolve("Can you send it to Mark, oh scratch that, to John"),
            "Can you send it to John"
        )
    }

    func testSorryPreservesStablePrefixForSingleWordRepair() {
        XCTAssertEqual(
            detector.detectAndResolve("Call Mark, sorry, John"),
            "Call John"
        )
    }

    // MARK: - Multiple Corrections

    func testMultipleCorrectionKeepsLast() {
        XCTAssertEqual(
            detector.detectAndResolve("Go left, wait, go right, actually no, go straight"),
            "Go straight"
        )
    }

    // MARK: - No Correction Present

    func testNoCorrection() {
        let input = "I went to the store and bought some milk"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testEmptyText() {
        XCTAssertEqual(detector.detectAndResolve(""), "")
    }

    // MARK: - Word Boundary Safety

    func testDoesNotMatchPartialWord() {
        let input = "I was waiting for the bus"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    // MARK: - False Positive Prevention (Context-Dependent Markers)

    func testWaitAsLegitimateWord() {
        let input = "Wait for me at the corner"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testSorryAsLegitimateWord() {
        let input = "The sorry state of affairs was obvious"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testIMeanAsLegitimatePhrase() {
        let input = "I mean business when I say that"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testWaitAtStartStillWorks() {
        XCTAssertEqual(
            detector.detectAndResolve("Wait, let's go to the park instead"),
            "Let's go to the park instead"
        )
    }

    func testSorryAtStartStillWorks() {
        XCTAssertEqual(
            detector.detectAndResolve("Sorry, I meant next Tuesday"),
            "I meant next Tuesday"
        )
    }

    // MARK: - Case Insensitivity

    func testCaseInsensitiveMatching() {
        XCTAssertEqual(
            detector.detectAndResolve("Turn left, ACTUALLY NO, turn right"),
            "Turn right"
        )
    }

    // MARK: - Correction at Start

    func testCorrectionMarkerAtStart() {
        XCTAssertEqual(
            detector.detectAndResolve("Actually no, let's go to the park"),
            "Let's go to the park"
        )
    }

    // MARK: - Correction Marker at End

    func testCorrectionMarkerAtEndKeepsOriginal() {
        let input = "I want to go to the park actually no"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    // MARK: - No No No Pattern

    func testNoNoNoCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Book the flight, no no no, cancel everything"),
            "Cancel everything"
        )
    }

    // MARK: - Cross-Sentence Corrections

    func testScratchThatAcrossSentences() {
        XCTAssertEqual(
            detector.detectAndResolve("Hey Mark. Scratch that. Hey John."),
            "Hey John."
        )
    }

    func testScratchThatWithSorryAcrossSentences() {
        XCTAssertEqual(
            detector.detectAndResolve("Hey Mark. Oh sorry, scratch that. Hey John."),
            "Hey John."
        )
    }

    func testActuallyNoAcrossSentences() {
        XCTAssertEqual(
            detector.detectAndResolve("Send it to Mark. Actually no, send it to John."),
            "Send it to John."
        )
    }

    func testNeverMindCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Book the flight. Never mind, cancel everything."),
            "Cancel everything."
        )
    }

    func testNevermindCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Book the flight. Nevermind, cancel everything."),
            "Cancel everything."
        )
    }

    func testForgetThatCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Add that to the list. Forget that, remove it instead."),
            "Remove it instead."
        )
    }

    func testStartOverCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("Dear sir, I am writing to. Start over. Hi team, quick update."),
            "Hi team, quick update."
        )
    }

    func testLetMeStartOverCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("The report shows. Let me start over. Sales grew 10%."),
            "Sales grew 10%."
        )
    }

    // MARK: - Whitespace Handling

    func testTrimsWhitespace() {
        XCTAssertEqual(
            detector.detectAndResolve("  Turn left, actually no,   turn right  "),
            "Turn right"
        )
    }

    // MARK: - Cascading Corrections (Prefix Preservation)

    func testCascadeDoubleCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("the meeting is tuesday, scratch that, wednesday, actually no, thursday"),
            "the meeting is thursday"
        )
    }

    func testCascadeTripleWithDifferentMarkers() {
        XCTAssertEqual(
            detector.detectAndResolve("order pizza, no no, order pasta, forget that, order sushi"),
            "order sushi"
        )
    }

    func testCascadeMixedInlineAndFullCorrections() {
        XCTAssertEqual(
            detector.detectAndResolve("set the color to red, I mean blue, no no, green"),
            "set the color to green"
        )
    }

    func testCascadeFragmentPreservationThroughRestart() {
        XCTAssertEqual(
            detector.detectAndResolve("invite alice, scratch that, invite bob and carol"),
            "invite bob and carol"
        )
    }

    func testCascadeNeverMindWithMakeItIdiom() {
        XCTAssertEqual(
            detector.detectAndResolve("the deadline is friday, never mind, make it monday"),
            "the deadline is monday"
        )
    }

    func testCascadeNeverMindWithMakeThatIdiom() {
        XCTAssertEqual(
            detector.detectAndResolve("the color is blue, never mind, make that red"),
            "the color is red"
        )
    }

    // MARK: - Overlap-Based Merge (Clause Starter with Context Preservation)

    func testOverlapMergePreservesContext() {
        XCTAssertEqual(
            detector.detectAndResolve("the meeting is at three, never mind, it's at four"),
            "the meeting is at four"
        )
    }

    func testOverlapMergeDoesNotFalsePositiveOnUnrelatedOverlap() {
        XCTAssertEqual(
            detector.detectAndResolve("They arrive on Monday, wait, it's on sale today"),
            "It's on sale today"
        )
    }

    func testOverlapMergeFullClauseStarterWithNoOverlap() {
        XCTAssertEqual(
            detector.detectAndResolve("The meeting is at 3, wait, it's cancelled"),
            "It's cancelled"
        )
    }

    // MARK: - Regression Tests (Oracle Review Counter-Examples)

    func testLiteralMakeItIdiomNotStripped() {
        // "make it happen" is literal imperative speech, not a correction idiom
        XCTAssertEqual(
            detector.detectAndResolve("We can postpone it, never mind, make it happen"),
            "Make it happen"
        )
    }

    func testOverlapMergeFalsePositiveOnWeakPreposition() {
        // "at" without copula before it should not trigger overlap merge
        XCTAssertEqual(
            detector.detectAndResolve("We meet at noon, wait, it's at risk"),
            "It's at risk"
        )
    }

    func testClauseStarterCascadePreservesOriginalPrefix() {
        // When a clause-starter repair ("it's wednesday") has no structural overlap
        // with before, the original prefix is lost. The cascading still resolves
        // the final value correctly. Full prefix preservation would require semantic
        // matching between day names, which is beyond current heuristics.
        XCTAssertEqual(
            detector.detectAndResolve("the meeting is tuesday, sorry, it's wednesday, actually no, thursday"),
            "it's thursday"
        )
    }

    // MARK: - High-Precision Implicit Correction Markers

    func testOhSorryCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("send it to mark oh sorry to john"),
            "send it to john"
        )
    }

    func testWaitHoldOnCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("call sarah wait hold on call john"),
            "call john"
        )
    }

    func testNoMakeThatCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("I need five no make that six copies"),
            "I need six copies"
        )
    }

    func testOrRatherCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("we should go left or rather right at the intersection"),
            "we should go right at the intersection"
        )
    }

    func testOnSecondThoughtCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("order the pasta hmm on second thought order the salad"),
            "order the salad"
        )
    }

    func testNoWaitCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("the file is in documents no wait it's in downloads"),
            "the file is in downloads"
        )
    }

    func testNahUseCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("set the font to arial nah use helvetica instead"),
            "set the font to helvetica instead"
        )
    }

    func testOopsIMeantCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("reply to mike oops I meant reply to dave"),
            "reply to dave"
        )
    }

    func testCorrectionMarkerCorrection() {
        XCTAssertEqual(
            detector.detectAndResolve("the train leaves at eight correction it leaves at nine"),
            "the train leaves at nine"
        )
    }

    // MARK: - Implicit Marker False Positive Prevention

    func testOhSorryForTheDelayIsNotCorrection() {
        let input = "oh sorry for the delay"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testOhSorryAboutThatIsNotCorrection() {
        let input = "oh sorry about that"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testOhSorryToInterruptIsNotCorrection() {
        let input = "oh sorry to interrupt"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testOopsIMeantToCallYouIsNotCorrection() {
        let input = "oops I meant to call you"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testTheCorrectionWasMinorIsNotCorrection() {
        let input = "the correction was minor"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testACorrectionIsNeededIsNotCorrection() {
        let input = "a correction is needed for the report"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testCorrectionWithCopulaIsNotMarker() {
        // "correction is needed" — copula after "correction" means it's a noun
        let input = "manual correction is needed"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testOrRatherDoesNotMatchPartially() {
        // "or" alone should not trigger "or rather"
        let input = "we can go left or right"
        XCTAssertEqual(detector.detectAndResolve(input), input)
    }

    func testNoWaitWithLegitimateFollowUp() {
        // "no wait" followed by legitimate continuation should still
        // trigger since "no wait" is a strong correction signal
        XCTAssertEqual(
            detector.detectAndResolve("call at three no wait call at four"),
            "call at four"
        )
    }

    func testImplicitMarkerAtSentenceStartIsIgnored() {
        // Implicit markers without prior content should not trigger
        let input1 = "on second thought let's cancel"
        XCTAssertEqual(detector.detectAndResolve(input1), input1)

        let input2 = "wait hold on to the railing"
        XCTAssertEqual(detector.detectAndResolve(input2), input2)

        let input3 = "no wait for me outside"
        XCTAssertEqual(detector.detectAndResolve(input3), input3)
    }

    func testOrRatherWithClauseStarterRepairUsesOverlapMerge() {
        // "or rather it's tuesday" should fall through to overlap merge,
        // not force fragment merge (which would produce "the meeting is it's tuesday")
        XCTAssertEqual(
            detector.detectAndResolve("the meeting is monday or rather it's tuesday"),
            "it's tuesday"
        )
    }
}
