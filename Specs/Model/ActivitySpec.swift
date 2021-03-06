////
///  ActivitySpec.swift
//

@testable import Ello
import Quick
import Nimble


class ActivitySpec: QuickSpec {
    override func spec() {
        describe("+fromJSON:") {

            context("notifications stream") {
                it("parses repost_notification") {
                    let parsedActivities = stubbedJSONDataArray("activity_streams_notifications", "activities")
                    let activity = Activity.fromJSON(parsedActivities[0]) as! Activity
                    let createdAtStr = "2014-06-15T00:00:00.000Z"
                    let createdAt = createdAtStr.toDate()!
                    // active record
                    expect(activity.id) == createdAtStr
                    expect(activity.createdAt) == createdAt
                    // required
                    expect(activity.kind) == Activity.Kind.repostNotification
                    expect(activity.subjectType) == Activity.SubjectType.post
                    // links
                    expect(activity.subject).to(beAKindOf(Post.self))
                }

                it("parses new_follower_post") {
                    let parsedActivities = stubbedJSONDataArray("activity_streams_notifications", "activities")
                    let activity = Activity.fromJSON(parsedActivities[1]) as! Activity
                    let createdAtStr = "2014-06-14T00:00:00.000Z"
                    let createdAt = createdAtStr.toDate()!
                    // active record
                    expect(activity.id) == createdAtStr
                    expect(activity.createdAt) == createdAt
                    // required
                    expect(activity.kind) == Activity.Kind.newFollowerPost
                    expect(activity.subjectType) == Activity.SubjectType.user
                    // links
                    expect(activity.subject).to(beAKindOf(User.self))
                }

                it("parses love_on_original_post_notification") {
                    let parsedActivities = stubbedJSONDataArray("activity_streams_notifications", "activities")
                    let activity = Activity.fromJSON(parsedActivities[2]) as! Activity
                    let createdAtStr = "2014-06-13T00:00:00.000Z"
                    let createdAt = createdAtStr.toDate()!
                    // active record
                    expect(activity.id) == createdAtStr
                    expect(activity.createdAt) == createdAt
                    // required
                    expect(activity.kind) == Activity.Kind.loveOnOriginalPostNotification
                    expect(activity.subjectType) == Activity.SubjectType.unknown
                    // links
                    expect(activity.subject).to(beAKindOf(Love.self))
                }
            }
        }

        context("NSCoding") {

            var filePath = ""
            if let url = URL(string: FileManager.ElloDocumentsDir()) {
                filePath = url.appendingPathComponent("ActivitySpec").absoluteString
            }

            afterEach {
                do {
                    try FileManager.default.removeItem(atPath: filePath)
                }
                catch {

                }
            }

            context("encoding") {

                it("encodes successfully") {
                    let activity: Activity = stub([:])
                    let wasSuccessfulArchived = NSKeyedArchiver.archiveRootObject(activity, toFile: filePath)
                    expect(wasSuccessfulArchived).to(beTrue())
                }
            }

            context("decoding") {

                it("decodes own post successfully") {
                    let expectedCreatedAt = Date()
                    let post: Post = stub(["id" : "768"])
                    let activity: Activity = stub([
                        "subject" : post,
                        "id" : "456",
                        "kind" : "own_post",
                        "subjectType" : "Post",
                        "createdAt" : expectedCreatedAt
                    ])

                    NSKeyedArchiver.archiveRootObject(activity, toFile: filePath)
                    let unArchivedActivity = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Activity

                    expect(unArchivedActivity).toNot(beNil())
                    expect(unArchivedActivity.version) == 1
                    // active record
                    expect(unArchivedActivity.id) == "456"
                    expect(unArchivedActivity.createdAt) == expectedCreatedAt
                    // required
                    expect(unArchivedActivity.kind) == Activity.Kind.ownPost
                    expect(unArchivedActivity.subjectType) == Activity.SubjectType.post
                    // links
                    let unArchivedPost = unArchivedActivity.subject as! Post
                    expect(unArchivedPost).to(beAKindOf(Post.self))
                    expect(unArchivedPost.id) == "768"
                }

                it("decodes friend post successfully") {
                    let expectedCreatedAt = Date()
                    let post: Post = stub(["id" : "768"])
                    let activity: Activity = stub([
                        "subject" : post,
                        "id" : "456",
                        "kind" : "friend_post",
                        "subjectType" : "Post",
                        "createdAt" : expectedCreatedAt
                        ])

                    NSKeyedArchiver.archiveRootObject(activity, toFile: filePath)
                    let unArchivedActivity = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Activity

                    expect(unArchivedActivity).toNot(beNil())
                    expect(unArchivedActivity.version) == 1
                    // active record
                    expect(unArchivedActivity.id) == "456"
                    expect(unArchivedActivity.createdAt) == expectedCreatedAt
                    // required
                    expect(unArchivedActivity.kind) == Activity.Kind.friendPost
                    expect(unArchivedActivity.subjectType) == Activity.SubjectType.post
                    // links
                    let unArchivedPost = unArchivedActivity.subject as! Post
                    expect(unArchivedPost).to(beAKindOf(Post.self))
                    expect(unArchivedPost.id) == "768"
                }

                it("decodes welcome post successfully") {
                    let expectedCreatedAt = Date()
                    let user: User = stub(["id" : "768"])
                    let activity: Activity = stub([
                        "subject" : user,
                        "id" : "456",
                        "kind" : "welcome_post",
                        "subjectType" : "User",
                        "createdAt" : expectedCreatedAt
                        ])

                    NSKeyedArchiver.archiveRootObject(activity, toFile: filePath)
                    let unArchivedActivity = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Activity

                    expect(unArchivedActivity).toNot(beNil())
                    expect(unArchivedActivity.version) == 1
                    // active record
                    expect(unArchivedActivity.id) == "456"
                    expect(unArchivedActivity.createdAt) == expectedCreatedAt
                    // required
                    expect(unArchivedActivity.kind) == Activity.Kind.welcomePost
                    expect(unArchivedActivity.subjectType) == Activity.SubjectType.user
                    // links
                    let unArchivedUser = unArchivedActivity.subject as! User
                    expect(unArchivedUser).to(beAKindOf(User.self))
                    expect(unArchivedUser.id) == "768"
                }

                it("decodes noise post successfully") {
                    let expectedCreatedAt = Date()
                    let post: Post = stub(["id" : "768"])
                    let activity: Activity = stub([
                        "subject" : post,
                        "id" : "456",
                        "kind" : "noise_post",
                        "subjectType" : "Post",
                        "createdAt" : expectedCreatedAt
                    ])

                    NSKeyedArchiver.archiveRootObject(activity, toFile: filePath)
                    let unArchivedActivity = NSKeyedUnarchiver.unarchiveObject(withFile: filePath) as! Activity

                    expect(unArchivedActivity).toNot(beNil())
                    expect(unArchivedActivity.version) == 1
                    // active record
                    expect(unArchivedActivity.id) == "456"
                    expect(unArchivedActivity.createdAt) == expectedCreatedAt
                    // required
                    expect(unArchivedActivity.kind) == Activity.Kind.noisePost
                    expect(unArchivedActivity.subjectType) == Activity.SubjectType.post
                    // links
                    let unArchivedPost = unArchivedActivity.subject as! Post
                    expect(unArchivedPost).to(beAKindOf(Post.self))
                    expect(unArchivedPost.id) == "768"
                }
            }
        }
    }
}

