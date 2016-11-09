////
///  CategoryGeneratorSpec.swift
//

import Ello
import Quick
import Nimble

class CategoryGeneratorSpec: QuickSpec {
    override func spec() {
        describe("CategoryGenerator") {
            let destination = CategoryDestination()

            beforeEach {
                destination.reset()
            }

            let currentUser: User = stub(["id": "42"])
            let streamKind: StreamKind = .Category(slug: "recommended")

            context("page promotional") {
                let category = Ello.Category.stub(["level" : "meta", "slug" : "recommended"])
                let subject = CategoryGenerator(
                    category: category,
                    currentUser: currentUser,
                    streamKind: streamKind,
                    destination: destination
                )

                describe("load()") {

                    it("sets 2 placeholders") {
                        subject.load()
                        expect(destination.placeholderItems.count) == 2
                    }

                    it("replaces only CatgoryHeader and CategoryPosts") {
                        subject.load()
                        expect(destination.headerItems.count) > 0
                        expect(destination.postItems.count) > 0
                        expect(destination.otherPlaceHolderLoaded) == false
                    }

                    it("sets the primary jsonable") {
                        subject.load()
                        expect(destination.category).to(beNil())
                        expect(destination.pagePromotional).toNot(beNil())
                    }

                    it("sets the config response") {
                        subject.load()
                        expect(destination.responseConfig).toNot(beNil())
                    }
                }
            }

            context("category") {
                let category = Ello.Category.stub(["level" : "primary"])
                let subject = CategoryGenerator(
                    category: category,
                    currentUser: currentUser,
                    streamKind: streamKind,
                    destination: destination
                )

                describe("load()") {

                    it("sets 2 placeholders") {
                        subject.load()
                        expect(destination.placeholderItems.count) == 2
                    }

                    it("replaces only CatgoryHeader and CategoryPosts") {
                        subject.load()
                        expect(destination.headerItems.count) > 0
                        expect(destination.postItems.count) > 0
                        expect(destination.otherPlaceHolderLoaded) == false
                    }

                    it("sets the primary jsonable") {
                        subject.load()
                        expect(destination.category).toNot(beNil())
                        expect(destination.pagePromotional).to(beNil())
                    }

                    it("sets the config response") {
                        subject.load()
                        expect(destination.responseConfig).toNot(beNil())
                    }
                }
            }
        }
    }
}

class CategoryDestination: StreamDestination {

    var placeholderItems: [StreamCellItem] = []
    var headerItems: [StreamCellItem] = []
    var postItems: [StreamCellItem] = []
    var otherPlaceHolderLoaded = false
    var category: Ello.Category?
    var pagePromotional: PagePromotional?
    var responseConfig: ResponseConfig?
    var pagingEnabled: Bool = false

    func reset() {
        placeholderItems = []
        headerItems = []
        postItems = []
        otherPlaceHolderLoaded = false
        category = nil
        pagePromotional = nil
        responseConfig = nil
    }

    func setPlaceholders(items: [StreamCellItem]) {
        placeholderItems = items
    }

    func replacePlaceholder(type: StreamCellType.PlaceholderType, items: [StreamCellItem], completion: ElloEmptyCompletion) {
        switch type {
        case .CategoryHeader:
            headerItems = items
        case .CategoryPosts:
            postItems = items
        default:
            otherPlaceHolderLoaded = true
        }
    }

    func setPrimaryJSONAble(jsonable: JSONAble) {
        if let category = jsonable as? Ello.Category {
            self.category = category
        }

        if let pagePromotional = jsonable as? PagePromotional {
            self.pagePromotional = pagePromotional
        }
    }

    func primaryJSONAbleNotFound() {
    }
    
    func setPagingConfig(responseConfig: ResponseConfig) {
        self.responseConfig = responseConfig
    }
}

