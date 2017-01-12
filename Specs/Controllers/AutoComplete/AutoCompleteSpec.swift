////
///  AutoCompleteSpec.swift
//

@testable import Ello
import Quick
import Nimble

import Result

class AutoCompleteSpec: QuickSpec {
    override func spec() {
        describe("AutoComplete") {
            let subject = AutoComplete()

            describe("check(_:location)") {

                context("empty") {
                    it("returns nil") {
                        let str = ""
                        let result = subject.check(str, location: 0)

                        expect(result).to(beNil())
                    }
                }

                context("single space") {
                    it("returns nil") {
                        let str = " "
                        let result = subject.check(str, location: 0)

                        expect(result).to(beNil())
                    }
                }

                context("neither") {
                    it("returns nil") {
                        let str = "nothing here to find"
                        let result = subject.check(str, location: 9)

                        expect(result).to(beNil())
                    }
                }

                context("username") {
                    it("returns the correct character range and string") {
                        let str = "@sean"
                        let result = subject.check(str, location: 3)

                        let endIndex = str.characters.index(str.startIndex, offsetBy: 3)

                        expect(result?.type) == AutoCompleteType.username
                        expect(result?.range) == str.startIndex..<endIndex
                        expect(result?.text) == "@se"
                    }
                }

                context("username in long string") {
                    it("returns the correct character range and string") {
                        let str = "hi there @sean"
                        let result = subject.check(str, location: 13)

                        let startIndex = str.characters.index(str.startIndex, offsetBy: 9)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 13)

                        expect(result?.type) == AutoCompleteType.username
                        expect(result?.range) == startIndex..<endIndex
                        expect(result?.text) == "@sea"
                    }
                }

                context("colon at end of word") {
                    it("returns nil") {
                        let str = "list:"
                        let result = subject.check(str, location: 6)

                        expect(result).to(beNil())
                    }
                }

                context("emoji") {
                    it("returns the correct character range and string") {
                        let str = "start :emoji"
                        let result = subject.check(str, location: 10)

                        let startIndex = str.characters.index(str.startIndex, offsetBy: 6)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 10)

                        expect(result?.type) == AutoCompleteType.emoji
                        expect(result?.range) == startIndex..<endIndex
                        expect(result?.text) == ":emo"
                    }
                }

                context("end of emoji") {
                    it("returns nil") {
                        let str = "start :emoji:"
                        let result = subject.check(str, location: 14)

                        expect(result).to(beNil())
                    }
                }

                context("double emoji") {
                    it("returns the 2nd emoji word part") {
                        let str = "some long sentence :start::thumbsup"
                        let result = subject.check(str, location: 30)

                        let startIndex = str.characters.index(str.startIndex, offsetBy: 26)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 30)

                        expect(result?.type) == AutoCompleteType.emoji
                        expect(result?.range) == startIndex..<endIndex
                        expect(result?.text) == ":thu"
                    }
                }

                context("location at the end of the string") {
                    it("returns the correct character range and string") {
                        let str = "@hi"
                        let result = subject.check(str, location: 3)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 3)
                        expect(result?.type) == AutoCompleteType.username
                        expect(result?.range) == str.startIndex..<endIndex
                        expect(result?.text) == "@hi"
                    }
                }

                context("whitespace after a match") {
                    it("returns nil") {
                        let str = "@username "
                        let result = subject.check(str, location: 10)

                        expect(result).to(beNil())
                    }
                }

                context("location out of bounds") {
                    it("returns nil") {
                        let str = "hi"
                        let result = subject.check(str, location: 101)

                        expect(result).to(beNil())
                    }
                }

                context("location one past the end") {
                    it("returns nil") {
                        let str = ":hi"
                        let result = subject.check(str, location: 4)

                        expect(result).to(beNil())
                    }
                }

                context("email address") {
                    it("returns nil") {
                        let str = "joe@example"
                        let result = subject.check(str, location: 10)

                        expect(result).to(beNil())
                    }
                }

                context("emoji already in string") {
                    it("returns nil") {
                        let str = ":+1:two"
                        let result = subject.check(str, location: 7)

                        expect(result).to(beNil())
                    }
                }

                context("emoji already in string, started new emoji") {
                    it("returns :two when separated by space") {
                        let str = ":+1: :two"
                        let result = subject.check(str, location: 9)

                        let startIndex = str.characters.index(str.startIndex, offsetBy: 5)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 9)

                        expect(result?.type) == AutoCompleteType.emoji
                        expect(result?.range) == startIndex..<endIndex
                        expect(result?.text) == ":two"
                    }
                    it("returns :two when emojis are touching") {
                        let str = ":+1::two"
                        let result = subject.check(str, location: 8)

                        let startIndex = str.characters.index(str.startIndex, offsetBy: 4)
                        let endIndex = str.characters.index(str.startIndex, offsetBy: 8)

                        expect(result?.type) == AutoCompleteType.emoji
                        expect(result?.range) == startIndex..<endIndex
                        expect(result?.text) == ":two"
                    }
                }
            }
        }
    }
}
