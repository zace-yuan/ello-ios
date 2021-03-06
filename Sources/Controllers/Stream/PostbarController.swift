////
///  PostbarController.swift
//

import Foundation


// swiftlint:enable colon

@objc
protocol PostbarResponder: class {
    func viewsButtonTapped(_ indexPath: IndexPath)
    func commentsButtonTapped(_ cell: StreamFooterCell, imageLabelControl: ImageLabelControl)
    func deleteCommentButtonTapped(_ indexPath: IndexPath)
    func editCommentButtonTapped(_ indexPath: IndexPath)
    func lovesButtonTapped(_ cell: StreamFooterCell?, indexPath: IndexPath)
    func repostButtonTapped(_ indexPath: IndexPath)
    func shareButtonTapped(_ indexPath: IndexPath, sourceView: UIView)
    func flagCommentButtonTapped(_ indexPath: IndexPath)
    func replyToCommentButtonTapped(_ indexPath: IndexPath)
    func replyToAllButtonTapped(_ indexPath: IndexPath)
    func watchPostTapped(_ watching: Bool, cell: StreamCreateCommentCell, indexPath: IndexPath)
}

class PostbarController: UIResponder, PostbarResponder {

    override var canBecomeFirstResponder: Bool {
        return true
    }

    override var next: UIResponder? {
        return responderChainable?.next()
    }

    var responderChainable: ResponderChainableController?
    var collectionView: UICollectionView
    let dataSource: StreamDataSource
    var currentUser: User?

    // on the post detail screen, the comments don't show/hide
    var toggleableComments: Bool = true

    init(collectionView: UICollectionView, dataSource: StreamDataSource) {
        self.collectionView = collectionView
        self.dataSource = dataSource
    }

    // MARK:

    func viewsButtonTapped(_ indexPath: IndexPath) {
        guard let post = postForIndexPath(indexPath) else { return }

        Tracker.shared.viewsButtonTapped(post: post)

        let responder = target(forAction: #selector(PostTappedResponder.postTapped(_:)), withSender: self) as? PostTappedResponder
        responder?.postTapped(post)
    }

    func commentsButtonTapped(_ cell: StreamFooterCell, imageLabelControl: ImageLabelControl) {
        guard !dataSource.streamKind.isGridView else {
            cell.cancelCommentLoading()
            if let indexPath = collectionView.indexPath(for: cell) {
                self.viewsButtonTapped(indexPath)
            }
            return
        }

        guard toggleableComments else {
            cell.cancelCommentLoading()
            return
        }

        guard
            let indexPath = collectionView.indexPath(for: cell),
            let item = dataSource.visibleStreamCellItem(at: indexPath),
            let post = item.jsonable as? Post
        else {
            cell.cancelCommentLoading()
            return
        }

        if let commentCount = post.commentsCount, commentCount == 0, currentUser == nil {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }

        guard !dataSource.streamKind.isDetail else {
            return
        }

        imageLabelControl.isSelected = cell.commentsOpened
        cell.commentsControl.isEnabled = false

        if !cell.commentsOpened {
            self.dataSource.removeCommentsFor(post: post)
            self.collectionView.reloadData()
            item.state = .collapsed
            imageLabelControl.isEnabled = true
            imageLabelControl.finishAnimation()
            imageLabelControl.isHighlighted = false
        }
        else {
            item.state = .loading
            imageLabelControl.isHighlighted = true
            imageLabelControl.animate()
            let streamService = StreamService()
            streamService.loadMoreCommentsForPost(
                post.id,
                streamKind: dataSource.streamKind,
                success: { [weak self] (comments, responseConfig) in
                    guard let `self` = self else { return }
                    if let updatedIndexPath = self.dataSource.indexPathForItem(item) {
                        item.state = .expanded
                        imageLabelControl.finishAnimation()
                        let nextIndexPath = IndexPath(item: updatedIndexPath.row + 1, section: updatedIndexPath.section)
                        self.commentLoadSuccess(post, comments: comments, indexPath: nextIndexPath, cell: cell)
                    }
                },
                failure: { _ in
                    item.state = .collapsed
                    imageLabelControl.finishAnimation()
                    cell.cancelCommentLoading()
                    print("comment load failure")
                },
                noContent: { [weak self] in
                    guard let `self` = self else { return }
                    item.state = .expanded
                    imageLabelControl.finishAnimation()
                    if let updatedIndexPath = self.dataSource.indexPathForItem(item) {
                        let nextIndexPath = IndexPath(item: updatedIndexPath.row + 1, section: updatedIndexPath.section)
                        self.commentLoadSuccess(post, comments: [], indexPath: nextIndexPath, cell: cell)
                    }
                })
        }
    }

    func deleteCommentButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }

        let message = InterfaceString.Post.DeleteCommentConfirm
        let alertController = AlertViewController(message: message)

        let yesAction = AlertAction(title: InterfaceString.Yes, style: .dark) {
            action in
            if let comment = self.commentForIndexPath(indexPath) {
                // comment deleted
                postNotification(CommentChangedNotification, value: (comment, .delete))
                // post comment count updated
                ContentChange.updateCommentCount(comment, delta: -1)
                PostService().deleteComment(comment.postId, commentId: comment.id,
                    success: {
                        Tracker.shared.commentDeleted(comment)
                    },
                    failure: { (error, statusCode)  in
                        // TODO: add error handling
                        print("failed to delete comment, error: \(error.elloErrorMessage ?? error.localizedDescription)")
                    })
            }
        }
        let noAction = AlertAction(title: InterfaceString.No, style: .light, handler: .none)

        alertController.addAction(yesAction)
        alertController.addAction(noAction)

        logPresentingAlert(responderChainable?.controller?.readableClassName() ?? "PostbarController")
        responderChainable?.controller?.present(alertController, animated: true, completion: .none)
    }

    func editCommentButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard
            let comment = commentForIndexPath(indexPath),
            let presentingController = responderChainable?.controller
        else { return }

        let responder = target(forAction: #selector(CreatePostResponder.editComment(_:fromController:)), withSender: self) as? CreatePostResponder
        responder?.editComment(comment, fromController: presentingController)
    }

    func lovesButtonTapped(_ cell: StreamFooterCell?, indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard let post = self.postForIndexPath(indexPath) else { return }
        cell?.lovesControl.isUserInteractionEnabled = false

        if post.loved { unlovePost(post, cell: cell) }
        else { lovePost(post, cell: cell) }
    }

    fileprivate func unlovePost(_ post: Post, cell: StreamFooterCell?) {
        Tracker.shared.postUnloved(post)
        if let count = post.lovesCount {
            post.lovesCount = count - 1
            post.loved = false
            postNotification(PostChangedNotification, value: (post, .loved))
        }
        if let user = currentUser, let userLoveCount = user.lovesCount {
            user.lovesCount = userLoveCount - 1
            postNotification(CurrentUserChangedNotification, value: user)
        }
        let service = LovesService()
        service.unlovePost(
            postId: post.id,
            success: {
                cell?.lovesControl.isUserInteractionEnabled = true
            },
            failure: { error, statusCode in
                cell?.lovesControl.isUserInteractionEnabled = true
                print("failed to unlove post \(post.id), error: \(error.elloErrorMessage ?? error.localizedDescription)")
            })
    }

    fileprivate func lovePost(_ post: Post, cell: StreamFooterCell?) {
        Tracker.shared.postLoved(post)
        if let count = post.lovesCount {
            post.lovesCount = count + 1
            post.loved = true
            postNotification(PostChangedNotification, value: (post, .loved))
        }
        if let user = currentUser, let userLoveCount = user.lovesCount {
            user.lovesCount = userLoveCount + 1
            postNotification(CurrentUserChangedNotification, value: user)
        }
        LovesService().lovePost(
            postId: post.id,
            success: { (love, responseConfig) in
                postNotification(JSONAbleChangedNotification, value: (love, .create))
                cell?.lovesControl.isUserInteractionEnabled = true
            },
            failure: { error, statusCode in
                cell?.lovesControl.isUserInteractionEnabled = true
                print("failed to love post \(post.id), error: \(error.elloErrorMessage ?? error.localizedDescription)")
            })
    }

    func repostButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard let post = self.postForIndexPath(indexPath) else { return }

        Tracker.shared.postReposted(post)
        let message = InterfaceString.Post.RepostConfirm
        let alertController = AlertViewController(message: message)
        alertController.autoDismiss = false

        let yesAction = AlertAction(title: InterfaceString.Yes, style: .dark) { action in
            self.createRepost(post, alertController: alertController)
        }
        let noAction = AlertAction(title: InterfaceString.No, style: .light) { action in
            alertController.dismiss()
        }

        alertController.addAction(yesAction)
        alertController.addAction(noAction)

        logPresentingAlert(responderChainable?.controller?.readableClassName() ?? "PostbarController")
        responderChainable?.controller?.present(alertController, animated: true, completion: .none)
    }

    fileprivate func createRepost(_ post: Post, alertController: AlertViewController) {
        alertController.resetActions()
        alertController.dismissable = false

        let spinnerContainer = UIView(frame: CGRect(x: 0, y: 0, width: alertController.view.frame.size.width, height: 200))
        let spinner = ElloLogoView(frame: CGRect(origin: .zero, size: ElloLogoView.Size.Natural))
        spinner.center = spinnerContainer.bounds.center
        spinnerContainer.addSubview(spinner)
        alertController.contentView = spinnerContainer
        spinner.animateLogo()
        if let user = currentUser, let userPostsCount = user.postsCount {
            user.postsCount = userPostsCount + 1
            postNotification(CurrentUserChangedNotification, value: user)
        }

        post.reposted = true
        if let repostsCount = post.repostsCount {
            post.repostsCount = repostsCount + 1
        }
        else {
            post.repostsCount = 1
        }
        ElloLinkedStore.sharedInstance.setObject(post, forKey: post.id, type: .postsType)
        postNotification(PostChangedNotification, value: (post, .reposted))

        RePostService().repost(post: post,
            success: { repost in
                postNotification(PostChangedNotification, value: (repost, .create))
                alertController.contentView = nil
                alertController.message = InterfaceString.Post.RepostSuccess
                delay(1) {
                    alertController.dismiss()
                }
            }, failure: { (error, statusCode)  in
                alertController.contentView = nil
                alertController.message = InterfaceString.Post.RepostError
                alertController.autoDismiss = true
                alertController.dismissable = true
                let okAction = AlertAction(title: InterfaceString.OK, style: .light, handler: .none)
                alertController.addAction(okAction)
            })
    }

    func shareButtonTapped(_ indexPath: IndexPath, sourceView: UIView) {
        guard
            let post = dataSource.postForIndexPath(indexPath),
            let shareLink = post.shareLink,
            let shareURL = URL(string: shareLink)
        else { return }

        Tracker.shared.postShared(post)
        let activityVC = UIActivityViewController(activityItems: [shareURL], applicationActivities: [SafariActivity()])
        if UI_USER_INTERFACE_IDIOM() == .phone {
            activityVC.modalPresentationStyle = .fullScreen
            logPresentingAlert(responderChainable?.controller?.readableClassName() ?? "PostbarController")
            responderChainable?.controller?.present(activityVC, animated: true) { }
        }
        else {
            activityVC.modalPresentationStyle = .popover
            activityVC.popoverPresentationController?.sourceView = sourceView
            logPresentingAlert(responderChainable?.controller?.readableClassName() ?? "PostbarController")
            responderChainable?.controller?.present(activityVC, animated: true) { }
        }
    }

    func flagCommentButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard
            let comment = commentForIndexPath(indexPath),
            let presentingController = responderChainable?.controller
        else { return }

        let flagger = ContentFlagger(
            presentingController: presentingController,
            flaggableId: comment.id,
            contentType: .comment,
            commentPostId: comment.postId
        )

        flagger.displayFlaggingSheet()
    }

    func replyToCommentButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard
            let comment = commentForIndexPath(indexPath),
            let presentingController = responderChainable?.controller,
            let atName = comment.author?.atName
        else { return }


        let postId = comment.loadedFromPostId

        let responder = target(forAction: #selector(CreatePostResponder.createComment(_:text:fromController:)), withSender: self) as? CreatePostResponder
        responder?.createComment(postId, text: "\(atName) ", fromController: presentingController)
    }

    func replyToAllButtonTapped(_ indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard
            let comment = commentForIndexPath(indexPath),
            let presentingController = responderChainable?.controller
        else { return }

        let postId = comment.loadedFromPostId
        PostService().loadReplyAll(postId, success: { [weak self] usernames in
            guard let `self` = self else { return }
            let usernamesText = usernames.reduce("") { memo, username in
                return memo + "@\(username) "
            }
            let responder = self.target(forAction: #selector(CreatePostResponder.createComment(_:text:fromController:)), withSender: self) as? CreatePostResponder
            responder?.createComment(postId, text: usernamesText, fromController: presentingController)
        }, failure: { [weak self] in
            guard let `self` = self else { return }
            guard let controller = self.responderChainable?.controller else { return }
            let responder = self.target(forAction: #selector(CreatePostResponder.createComment(_:text:fromController:)), withSender: self) as? CreatePostResponder
            responder?.createComment(postId, text: nil, fromController: controller)
        })
    }

    func watchPostTapped(_ watching: Bool, cell: StreamCreateCommentCell, indexPath: IndexPath) {
        guard currentUser != nil else {
            postNotification(LoggedOutNotifications.userActionAttempted, value: .postTool)
            return
        }
        guard
            let comment = dataSource.commentForIndexPath(indexPath),
            let post = comment.parentPost
        else { return }

        cell.watching = watching
        cell.isUserInteractionEnabled = false
        PostService().toggleWatchPost(post, watching: watching)
            .onSuccess { post in
                cell.isUserInteractionEnabled = true
                postNotification(PostChangedNotification, value: (post, .watching))
            }
            .onFail { error in
                cell.isUserInteractionEnabled = true
                cell.watching = !watching
            }
    }

// MARK: - Private

    fileprivate func postForIndexPath(_ indexPath: IndexPath) -> Post? {
        return dataSource.postForIndexPath(indexPath)
    }

    fileprivate func commentForIndexPath(_ indexPath: IndexPath) -> ElloComment? {
        return dataSource.commentForIndexPath(indexPath)
    }

    fileprivate func commentLoadSuccess(_ post: Post, comments jsonables: [JSONAble], indexPath: IndexPath, cell: StreamFooterCell) {
        self.appendCreateCommentItem(post, at: indexPath)
        let commentsStartingIndexPath = IndexPath(row: indexPath.row + 1, section: indexPath.section)

        var items = StreamCellItemParser().parse(jsonables, streamKind: StreamKind.following, currentUser: currentUser)

        if let currentUser = currentUser {
            let newComment = ElloComment.newCommentForPost(post, currentUser: currentUser)
            if let maxCount = ElloAPI.postComments(postId: "").parameters!["per_page"] as? Int,
                let postCommentCount = post.commentsCount,
                postCommentCount > maxCount
            {
                items.append(StreamCellItem(jsonable: jsonables.last ?? newComment, type: .seeMoreComments))
            }
            else {
                items.append(StreamCellItem(jsonable: newComment, type: .spacer(height: 10.0)))
            }
        }

        self.dataSource.insertUnsizedCellItems(items,
            withWidth: self.collectionView.frame.width,
            startingIndexPath: commentsStartingIndexPath) { [weak self] (indexPaths) in
                guard let `self` = self else { return }
                self.collectionView.reloadData() // insertItemsAtIndexPaths(indexPaths)
                cell.commentsControl.isEnabled = true

                if let controller = self.responderChainable?.controller,
                    indexPaths.count == 1, jsonables.count == 0, self.currentUser != nil
                {
                    let responder = self.target(forAction: #selector(CreatePostResponder.createComment(_:text:fromController:)), withSender: self) as? CreatePostResponder
                    responder?.createComment(post.id, text: nil, fromController: controller)
                }
            }
    }

    fileprivate func appendCreateCommentItem(_ post: Post, at indexPath: IndexPath) {
        guard let currentUser = currentUser else { return }

        let comment = ElloComment.newCommentForPost(post, currentUser: currentUser)
        let createCommentItem = StreamCellItem(jsonable: comment, type: .createComment)

        let items = [createCommentItem]
        self.dataSource.insertStreamCellItems(items, startingIndexPath: indexPath)
        self.collectionView.reloadData() // insertItemsAtIndexPaths([indexPath]) //
    }

    fileprivate func commentLoadFailure(_ error: NSError, statusCode: Int?) {
    }

}
