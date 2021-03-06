////
///  StreamViewController.swift
//

import SSPullToRefresh
import FLAnimatedImage
import Crashlytics
import SwiftyUserDefaults
import DeltaCalculator
import SnapKit


// MARK: Responder Implementations

@objc
protocol SimpleStreamResponder: class {
    func showSimpleStream(boxedEndpoint: BoxedElloAPI, title: String, noResultsMessages: NoResultsMessages?)
}

@objc
protocol StreamImageCellResponder: class {
    func imageTapped(imageView: FLAnimatedImageView, cell: StreamImageCell)
}

@objc
protocol StreamEditingResponder: class {
    func cellDoubleTapped(cell: UICollectionViewCell, location: CGPoint)
    func cellLongPressed(cell: UICollectionViewCell)
}

typealias StreamCellItemGenerator = () -> [StreamCellItem]
protocol StreamViewDelegate: class {
    func streamViewCustomLoadFailed() -> Bool
    func streamViewStreamCellItems(jsonables: [JSONAble], defaultGenerator: StreamCellItemGenerator) -> [StreamCellItem]?
    func streamViewDidScroll(scrollView: UIScrollView)
    func streamViewWillBeginDragging(scrollView: UIScrollView)
    func streamViewDidEndDragging(scrollView: UIScrollView, willDecelerate: Bool)
}

@objc
protocol CategoryResponder: class {
    func categoryCellTapped(cell: UICollectionViewCell)
}

@objc
protocol SelectedCategoryResponder: class {
    func categoriesSelectionChanged(selection: [Category])
}

@objc
protocol UserResponder: class {
    func userTappedAuthor(cell: UICollectionViewCell)
    func userTappedReposter(cell: UICollectionViewCell)
    func userTappedText(cell: UICollectionViewCell)
    func userTapped(user: User)
}

@objc
protocol WebLinkResponder: class {
    func webLinkTapped(path: String, type: ElloURIWrapper, data: String)
}

@objc
protocol GridListToggleDelegate: class {
    func gridListToggled(_ sender: UIButton)
}

@objc
protocol CategoryListCellResponder: class {
    func categoryListCellTapped(slug: String, name: String)
}

@objc
protocol SearchStreamResponder: class {
    func searchFieldChanged(text: String)
}

@objc
protocol AnnouncementCellResponder: class {
    func markAnnouncementAsRead(cell: UICollectionViewCell)
}

@objc
protocol AnnouncementResponder: class {
    func markAnnouncementAsRead(announcement: Announcement)
}


// MARK: StreamNotification
struct StreamNotification {
    static let AnimateCellHeightNotification = TypedNotification<StreamImageCell>(name: "AnimateCellHeightNotification")
    static let UpdateCellHeightNotification = TypedNotification<UICollectionViewCell>(name: "UpdateCellHeightNotification")
}

// This is an NSObject in order to pass it as an
// objective-c argument to a responder chain call
class NoResultsMessages: NSObject {
    let title: String
    let body: String
    init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

// MARK: StreamViewController
final class StreamViewController: BaseElloViewController {
    override func trackerName() -> String? { return nil }

    let collectionView = ElloCollectionView(frame: .zero, collectionViewLayout: StreamCollectionViewLayout())
    let noResultsLabel = UILabel()
    var noResultsTopConstraint: NSLayoutConstraint!
    fileprivate let defaultNoResultsTopConstant: CGFloat = 113

    var currentJSONables = [JSONAble]()

    var noResultsMessages: NoResultsMessages = NoResultsMessages(title: "", body: "") {
        didSet {
            let titleParagraphStyle = NSMutableParagraphStyle()
            titleParagraphStyle.lineSpacing = 17

            let titleAttributes = [
                NSFontAttributeName: UIFont.defaultBoldFont(18),
                NSForegroundColorAttributeName: UIColor.black,
                NSParagraphStyleAttributeName: titleParagraphStyle
            ]

            let bodyParagraphStyle = NSMutableParagraphStyle()
            bodyParagraphStyle.lineSpacing = 8

            let bodyAttributes = [
                NSFontAttributeName: UIFont.defaultFont(),
                NSForegroundColorAttributeName: UIColor.black,
                NSParagraphStyleAttributeName: bodyParagraphStyle
            ]

            let title = NSAttributedString(string: self.noResultsMessages.title + "\n", attributes: titleAttributes)
            let body = NSAttributedString(string: self.noResultsMessages.body, attributes: bodyAttributes)
            self.noResultsLabel.attributedText = title.appending(body)
        }
    }

    typealias ToggleClosure = (Bool) -> Void

    var dataSource: StreamDataSource!
    var postbarController: PostbarController?
    var responseConfig: ResponseConfig?
    var pagingEnabled = false
    fileprivate var scrollToPaginateGuard = false

    let streamService = StreamService()
    lazy var loadingToken: LoadingToken = self.createLoadingToken()

    // moved into a separate function to save compile time
    fileprivate func createLoadingToken() -> LoadingToken {
        var token = LoadingToken()
        token.cancelLoadingClosure = { [unowned self] in
            self.doneLoading()
        }
        return token
    }

    var pullToRefreshView: SSPullToRefreshView?
    var allOlderPagesLoaded = false
    var initialLoadClosure: ElloEmptyCompletion?
    var reloadClosure: ElloEmptyCompletion?
    var toggleClosure: ToggleClosure?
    var initialDataLoaded = false

    var streamKind: StreamKind = StreamKind.unknown {
        didSet {
            dataSource.streamKind = streamKind
            setupCollectionViewLayout()
        }
    }
    var imageViewer: StreamImageViewer?
    var updatedStreamImageCellHeightNotification: NotificationObserver?
    var updateCellHeightNotification: NotificationObserver?
    var rotationNotification: NotificationObserver?
    var sizeChangedNotification: NotificationObserver?
    var commentChangedNotification: NotificationObserver?
    var postChangedNotification: NotificationObserver?
    var jsonableChangedNotification: NotificationObserver?
    var relationshipChangedNotification: NotificationObserver?
    var settingChangedNotification: NotificationObserver?
    var currentUserChangedNotification: NotificationObserver?

    weak var streamViewDelegate: StreamViewDelegate?

    var streamFilter: StreamDataSource.StreamFilter {
        get { return dataSource.streamFilter }
        set {
            dataSource.streamFilter = newValue
            self.reloadCells(now: true)
            self.scrollToTop()
        }
    }

    func batchUpdateFilter(_ filter: StreamDataSource.StreamFilter) {
        let delta = dataSource.updateFilter(filter)
        collectionView.performBatchUpdates({
            delta.applyUpdatesToCollectionView(self.collectionView, inSection: 0)
        }, completion: nil)
    }

    var contentInset: UIEdgeInsets {
        get { return collectionView.contentInset }
        set {
            // the order here is important, because SSPullToRefresh will try to
            // set the contentInset, and that can have weird side effects, so
            // we need to set the contentInset *after* pullToRefreshView.
            pullToRefreshView?.defaultContentInset = newValue
            collectionView.contentInset = newValue
            collectionView.scrollIndicatorInsets = newValue
        }
    }
    var columnCount: Int {
        guard let layout = collectionView.collectionViewLayout as? StreamCollectionViewLayout else {
            return 1
        }
        return layout.columnCount
    }

    var pullToRefreshEnabled: Bool = true {
        didSet { pullToRefreshView?.isHidden = !pullToRefreshEnabled }
    }

    required init() {
        super.init(nibName: nil, bundle: nil)
        initialSetup()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didSetCurrentUser() {
        dataSource.currentUser = currentUser
        postbarController?.currentUser = currentUser
        super.didSetCurrentUser()
    }

    // If we ever create an init() method that doesn't use nib/storyboards,
    // we'll need to call this.
    fileprivate func initialSetup() {
        setupDataSource()
        setupImageViewDelegate()
        // most consumers of StreamViewController expect all outlets (esp collectionView) to be set
        if !isViewLoaded { let _ = view }
    }

    deinit {
        removeNotificationObservers()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        pullToRefreshView = SSPullToRefreshView(scrollView: collectionView, delegate: self)
        pullToRefreshView?.contentView = ElloPullToRefreshView(frame: .zero)
        pullToRefreshView?.isHidden = !pullToRefreshEnabled

        setupCollectionView()
        addNotificationObservers()
    }

    override func loadView() {
        super.loadView()
        view.addSubview(collectionView)
        view.addSubview(noResultsLabel)

        collectionView.snp.makeConstraints { make in
            make.edges.equalTo(self.view)
        }

        noResultsLabel.snp.makeConstraints { make in
            let c = make.top.equalTo(self.view).constraint
            self.noResultsTopConstraint = c.layoutConstraints.first!
            make.leading.trailing.equalTo(self.view).inset(15)
        }
        view.layoutIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Crashlytics.sharedInstance().setObjectValue(streamKind.name, forKey: CrashlyticsKey.streamName.rawValue)
    }

// MARK: Public Functions

    func scrollToTop() {
        collectionView.contentOffset = CGPoint(x: 0, y: contentInset.top)
    }

    func doneLoading() {
        ElloHUD.hideLoadingHudInView(view)
        pullToRefreshView?.finishLoading()
        initialDataLoaded = true
        updateNoResultsLabel()
    }

    fileprivate var debounceCellReload = debounce(0.05)
    func reloadCells(now: Bool = false) {
        if now {
            debounceCellReload {}
            self.collectionView.reloadData()
            self.collectionView.layoutIfNeeded()
        }
        else {
            debounceCellReload {
                self.collectionView.reloadData()
                self.collectionView.layoutIfNeeded()
            }
        }
    }

    func removeAllCellItems() {
        dataSource.removeAllCellItems()
        reloadCells(now: true)
    }

    func imageCellHeightUpdated(_ cell: StreamImageCell) {
        if let indexPath = collectionView.indexPath(for: cell),
            let calculatedHeight = cell.calculatedHeight
        {
            updateCellHeight(indexPath, height: calculatedHeight)
        }
    }

    func appendStreamCellItems(_ items: [StreamCellItem]) {
        dataSource.appendStreamCellItems(items)
        reloadCells(now: true)
    }

    func appendUnsizedCellItems(_ items: [StreamCellItem], completion: StreamDataSource.StreamContentReady? = nil) {
        let width = view.frame.width
        dataSource.appendUnsizedCellItems(items, withWidth: width) { indexPaths in
            self.reloadCells()
            self.doneLoading()
            completion?(indexPaths)
        }
    }

    func insertUnsizedCellItems(_ cellItems: [StreamCellItem], startingIndexPath: IndexPath, completion: @escaping ElloEmptyCompletion = {}) {
        let width = view.frame.width
        dataSource.insertUnsizedCellItems(cellItems, withWidth: width, startingIndexPath: startingIndexPath) { _ in
            self.reloadCells()
            completion()
        }
    }

    func hasCellItems(for placeholderType: StreamCellType.PlaceholderType) -> Bool {
        return dataSource.hasCellItems(for: placeholderType)
    }

    func replacePlaceholder(
        _ placeholderType: StreamCellType.PlaceholderType,
        with streamCellItems: [StreamCellItem],
        completion: @escaping ElloEmptyCompletion = {}
        )
    {
        guard streamCellItems.count > 0 else {
            replacePlaceholder(placeholderType, with: [StreamCellItem(type: .placeholder, placeholderType: placeholderType)], completion: completion)
            return
        }

        for item in streamCellItems {
            item.placeholderType = placeholderType
        }

        let width = view.frame.width
        dataSource.calculateCellItems(streamCellItems, withWidth: width) {
            let indexPathsToReplace = self.dataSource.indexPathsForPlaceholderType(placeholderType)
            guard indexPathsToReplace.count > 0 else { return }

            _ = self.dataSource.replaceItems(at: indexPathsToReplace, with: streamCellItems)
            self.reloadCells()
            completion()
        }
    }

    func loadInitialPage(reload: Bool = false) {
        if let reloadClosure = reloadClosure, reload {
            responseConfig = nil
            pagingEnabled = false
            reloadClosure()
        }
        else if let initialLoadClosure = initialLoadClosure {
            initialLoadClosure()
        }
        else {
            let localToken = loadingToken.resetInitialPageLoadingToken()

            streamService.loadStream(
                streamKind: streamKind,
                success: { (jsonables, responseConfig) in
                    guard self.loadingToken.isValidInitialPageLoadingToken(localToken) else { return }

                    self.responseConfig = responseConfig
                    self.showInitialJSONAbles(jsonables)
                }, failure: { (error, statusCode) in
                    print("failed to load \(self.streamKind.cacheKey) stream (reason: \(error))")
                    self.initialLoadFailure()
                }, noContent: {
                    self.showInitialJSONAbles([])
                })
        }
    }

    /// This method can be called by a `StreamableViewController` if it wants to
    /// override `loadInitialPage`, but doesn't need to customize the cell generation.
    func showInitialJSONAbles(_ jsonables: [JSONAble]) {
        self.clearForInitialLoad()
        self.currentJSONables = jsonables

        var items = self.generateStreamCellItems(jsonables)
        if jsonables.count == 0 {
            items.append(StreamCellItem(type: .emptyStream(height: 282)))
        }
        self.appendUnsizedCellItems(items) { indexPaths in
            self.pagingEnabled = true
        }
    }

    fileprivate func generateStreamCellItems(_ jsonables: [JSONAble]) -> [StreamCellItem] {
        let defaultGenerator: StreamCellItemGenerator = {
            return StreamCellItemParser().parse(jsonables, streamKind: self.streamKind, currentUser: self.currentUser)
        }

        if let items = streamViewDelegate?.streamViewStreamCellItems(jsonables: jsonables, defaultGenerator: defaultGenerator) {
            return items
        }

        return defaultGenerator()
    }

    fileprivate func updateNoResultsLabel() {
        let shouldShowNoResults = dataSource.visibleCellItems.count == 0
        if shouldShowNoResults {
            delay(0.666) {
                self.showNoResults()
            }
        }
        else {
            self.hideNoResults()
        }
    }

    func hideNoResults() {
        noResultsLabel.isHidden = true
        noResultsLabel.alpha = 0
    }

    func showNoResults() {
        noResultsLabel.isHidden = false
        UIView.animate(withDuration: 0.25, animations: {
            self.noResultsLabel.alpha = 1
        })
    }

    func clearForInitialLoad() {
        allOlderPagesLoaded = false
        dataSource.removeAllCellItems()
        reloadCells(now: true)
    }

// MARK: Private Functions

    fileprivate func initialLoadFailure() {
        guard streamViewDelegate?.streamViewCustomLoadFailed() == false else {
            return
        }
        self.doneLoading()

        var isVisible = false
        var view: UIView? = self.view
        while view != nil {
            if view is UIWindow {
                isVisible = true
                break
            }

            view = view!.superview
        }

        if isVisible {
            let message = InterfaceString.GenericError
            let alertController = AlertViewController(message: message)
            let action = AlertAction(title: InterfaceString.OK, style: .dark, handler: nil)
            alertController.addAction(action)
            logPresentingAlert("StreamViewController")
            present(alertController, animated: true) {
                if let navigationController = self.navigationController, navigationController.childViewControllers.count > 1 {
                    _ = navigationController.popViewController(animated: true)
                }
            }
        }
        else if let navigationController = navigationController, navigationController.childViewControllers.count > 1 {
            _ = navigationController.popViewController(animated: false)
        }
    }

    fileprivate func addNotificationObservers() {
        updatedStreamImageCellHeightNotification = NotificationObserver(notification: StreamNotification.AnimateCellHeightNotification) { [weak self] streamImageCell in
            guard let `self` = self else { return }
            self.imageCellHeightUpdated(streamImageCell)
        }
        updateCellHeightNotification = NotificationObserver(notification: StreamNotification.UpdateCellHeightNotification) { [weak self] streamTextCell in
            guard let `self` = self else { return }
            self.collectionView.collectionViewLayout.invalidateLayout()
        }
        rotationNotification = NotificationObserver(notification: Application.Notifications.DidChangeStatusBarOrientation) { [weak self] _ in
            guard let `self` = self else { return }
            self.reloadCells()
        }
        sizeChangedNotification = NotificationObserver(notification: Application.Notifications.ViewSizeWillChange) { [weak self] size in
            guard let `self` = self else { return }

            if let layout = self.collectionView.collectionViewLayout as? StreamCollectionViewLayout {
                layout.columnCount = self.streamKind.columnCountFor(width: size.width)
                layout.invalidateLayout()
            }
            self.reloadCells()
        }

        commentChangedNotification = NotificationObserver(notification: CommentChangedNotification) { [weak self] (comment, change) in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            switch change {
            case .create, .delete, .update, .replaced:
                self.dataSource.modifyItems(comment, change: change, collectionView: self.collectionView)
            default: break
            }
            self.updateNoResultsLabel()
        }

        postChangedNotification = NotificationObserver(notification: PostChangedNotification) { [weak self] (post, change) in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            switch change {
            case .delete:
                switch self.streamKind {
                case .postDetail: break
                default:
                    self.dataSource.modifyItems(post, change: change, collectionView: self.collectionView)
                }
                // reload page
            case .create,
                .update,
                .replaced,
                .loved,
                .reposted,
                .watching:
                self.dataSource.modifyItems(post, change: change, collectionView: self.collectionView)
            case .read: break
            }
            self.updateNoResultsLabel()
        }

        jsonableChangedNotification = NotificationObserver(notification: JSONAbleChangedNotification) { [weak self] (jsonable, change) in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            self.dataSource.modifyItems(jsonable, change: change, collectionView: self.collectionView)
            self.updateNoResultsLabel()
        }

        relationshipChangedNotification = NotificationObserver(notification: RelationshipChangedNotification) { [weak self] user in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            self.dataSource.modifyUserRelationshipItems(user, collectionView: self.collectionView)
            self.updateNoResultsLabel()
        }

        settingChangedNotification = NotificationObserver(notification: SettingChangedNotification) { [weak self] user in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            self.dataSource.modifyUserSettingsItems(user, collectionView: self.collectionView)
            self.updateNoResultsLabel()
        }

        currentUserChangedNotification = NotificationObserver(notification: CurrentUserChangedNotification) { [weak self] user in
            guard
                let `self` = self, self.initialDataLoaded && self.isViewLoaded
            else { return }

            self.dataSource.modifyItems(user, change: .update, collectionView: self.collectionView)
            self.updateNoResultsLabel()
        }
    }

    fileprivate func removeNotificationObservers() {
        updatedStreamImageCellHeightNotification?.removeObserver()
        updateCellHeightNotification?.removeObserver()
        rotationNotification?.removeObserver()
        sizeChangedNotification?.removeObserver()
        commentChangedNotification?.removeObserver()
        postChangedNotification?.removeObserver()
        relationshipChangedNotification?.removeObserver()
        jsonableChangedNotification?.removeObserver()
        settingChangedNotification?.removeObserver()
        currentUserChangedNotification?.removeObserver()
    }

    fileprivate func updateCellHeight(_ indexPath: IndexPath, height: CGFloat) {
        let existingHeight = dataSource.heightForIndexPath(indexPath, numberOfColumns: columnCount)
        if height != existingHeight {
            self.dataSource.updateHeightForIndexPath(indexPath, height: height)
            // collectionView.performBatchUpdates({
            //     collectionView.reloadItemsAtIndexPaths([indexPath])
            // }, completion: nil)
            collectionView.reloadData()
        }
    }

    override var next: UIResponder? {
        return postbarController
    }

    fileprivate func setupCollectionView() {
        let postbarController = PostbarController(collectionView: collectionView, dataSource: dataSource)
        postbarController.currentUser = currentUser

        // next is a closure due to the need
        // to lazily evaluate it at runtime. `super.next` is not available
        // at assignment but is present when the responder is used later on
        let chainableController = ResponderChainableController(
            controller: self,
            next: { [weak self] in
                return self?.superNext
            }
        )

        postbarController.responderChainable = chainableController
        self.postbarController = postbarController

        collectionView.dataSource = dataSource
        collectionView.delegate = self
        automaticallyAdjustsScrollViewInsets = false
        collectionView.alwaysBounceHorizontal = false
        collectionView.alwaysBounceVertical = true
        collectionView.isDirectionalLockEnabled = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColor = .clear

        StreamCellType.registerAll(collectionView)
        setupCollectionViewLayout()
    }

    // this gets reset whenever the streamKind changes
    fileprivate func setupCollectionViewLayout() {
        guard let layout = collectionView.collectionViewLayout as? StreamCollectionViewLayout else { return }
        layout.columnCount = streamKind.columnCountFor(width: view.frame.width)
        layout.sectionInset = UIEdgeInsets.zero
        layout.minimumColumnSpacing = streamKind.columnSpacing
        layout.minimumInteritemSpacing = 0
    }

    fileprivate func setupImageViewDelegate() {
        if imageViewer == nil {
            imageViewer = StreamImageViewer(presentingController: self)
        }
    }

    fileprivate func setupDataSource() {
        dataSource = StreamDataSource(
            streamKind: streamKind,
            textSizeCalculator: StreamTextCellSizeCalculator(webView: UIWebView()),
            notificationSizeCalculator: StreamNotificationCellSizeCalculator(webView: UIWebView()),
            announcementSizeCalculator: AnnouncementCellSizeCalculator(),
            profileHeaderSizeCalculator: ProfileHeaderCellSizeCalculator(),
            imageSizeCalculator: StreamImageCellSizeCalculator(),
            categoryHeaderSizeCalculator: CategoryHeaderCellSizeCalculator()

        )

        dataSource.streamCollapsedFilter = { item in
            if !item.type.collapsable {
                return true
            }
            if item.jsonable is Post {
                return item.state != .collapsed
            }
            return true
        }
    }

}

// MARK: DELEGATE & RESPONDER EXTENSIONS


// MARK: StreamViewController: GridListToggleDelegate
extension StreamViewController: GridListToggleDelegate {
    func gridListToggled(_ sender: UIButton) {
        let isGridView = !streamKind.isGridView
        sender.setImage(isGridView ? .listView : .gridView, imageStyle: .normal, for: .normal)
        streamKind.setIsGridView(isGridView)
        if let toggleClosure = toggleClosure {
            // setting 'scrollToPaginateGuard' to false will prevent pagination from triggering when this profile has no posts
            // triggering pagination at this time will, inexplicably, cause the cells to disappear
            scrollToPaginateGuard = false
            setupCollectionViewLayout()

            toggleClosure(isGridView)
        }
        else {
            UIView.animate(withDuration: 0.2, animations: {
                self.collectionView.alpha = 0
            }, completion: { _ in
                self.toggleGrid(isGridView: isGridView)
            })
        }
    }

    fileprivate func toggleGrid(isGridView: Bool) {
        var emptyStreamCellItem: StreamCellItem?
        if let first = dataSource.visibleCellItems.first {
            switch first.type {
            case .emptyStream: emptyStreamCellItem = first
            default: break
            }
        }

        self.removeAllCellItems()
        var items = generateStreamCellItems(self.currentJSONables)

        if let item = emptyStreamCellItem, items.count == 0 {
            items = [item]
        }

        self.appendUnsizedCellItems(items) { indexPaths in
            animate {
                self.collectionView.alpha = 1
            }
        }
        self.setupCollectionViewLayout()
    }
}

// MARK: StreamViewController: CategoryListCellResponder
extension StreamViewController: CategoryListCellResponder {

    func categoryListCellTapped(slug: String, name: String) {
        showCategoryViewController(slug: slug, name: name)
    }

}

// MARK: StreamViewController: SimpleStreamResponder
extension StreamViewController: SimpleStreamResponder {

    func showSimpleStream(boxedEndpoint: BoxedElloAPI, title: String, noResultsMessages: NoResultsMessages? = nil) {
        let vc = SimpleStreamViewController(endpoint: boxedEndpoint.endpoint, title: title)
        vc.currentUser = currentUser
        if let messages = noResultsMessages {
            vc.streamViewController.noResultsMessages = messages
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: StreamViewController: SSPullToRefreshViewDelegate
extension StreamViewController: SSPullToRefreshViewDelegate {

    func pull(toRefreshViewShouldStartLoading view: SSPullToRefreshView!) -> Bool {
        return pullToRefreshEnabled
    }

    func pull(_ view: SSPullToRefreshView, didTransitionTo toState: SSPullToRefreshViewState, from fromState: SSPullToRefreshViewState, animated: Bool) {
        if toState == .loading {
            if pullToRefreshEnabled {
                if let controller = parent as? BaseElloViewController {
                    Tracker.shared.screenAppeared(controller)
                }
                self.loadInitialPage(reload: true)
            }
            else {
                pullToRefreshView?.finishLoading()
            }
        }
    }

}

// MARK: StreamViewController: StreamCollectionViewLayoutDelegate
extension StreamViewController: StreamCollectionViewLayoutDelegate {

    func collectionView(_ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAtIndexPath indexPath: IndexPath) -> CGSize {
            let width = calculateColumnWidth(frameWidth: UIWindow.windowWidth(), columnCount: columnCount)
            let height = dataSource.heightForIndexPath(indexPath, numberOfColumns: 1)
            return CGSize(width: width, height: height)
    }

    func collectionView(_ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        groupForItemAtIndexPath indexPath: IndexPath) -> String? {
            return dataSource.groupForIndexPath(indexPath)
    }

    func collectionView(_ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        heightForItemAtIndexPath indexPath: IndexPath, numberOfColumns: NSInteger) -> CGFloat {
            return dataSource.heightForIndexPath(indexPath, numberOfColumns: numberOfColumns)
    }

    func collectionView (_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
        isFullWidthAtIndexPath indexPath: IndexPath) -> Bool {
            return dataSource.isFullWidthAtIndexPath(indexPath)
    }
}

// MARK: StreamViewController: StreamEditingResponder
extension StreamViewController: StreamEditingResponder {
    func cellDoubleTapped(cell: UICollectionViewCell, location: CGPoint) {
        guard let path = collectionView.indexPath(for: cell),
            let post = dataSource.postForIndexPath(path),
            let footerPath = dataSource.footerIndexPathForPost(post),
            post.author?.hasLovesEnabled == true
        else { return }

        if let window = cell.window {
            let fullDuration: TimeInterval = 0.4
            let halfDuration: TimeInterval = fullDuration / 2

            let imageView = UIImageView(image: InterfaceImage.giantHeart.normalImage)
            imageView.contentMode = .scaleAspectFit
            imageView.frame = window.bounds
            imageView.center = location
            imageView.alpha = 0
            imageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            let grow: () -> Void = { imageView.transform = CGAffineTransform(scaleX: 1, y: 1) }
            let remove: (Bool) -> Void = { _ in imageView.removeFromSuperview() }
            let fadeIn: () -> Void = { imageView.alpha = 0.5 }
            let fadeOut: (Bool) -> Void = { _ in animate(duration: halfDuration, completion: remove) { imageView.alpha = 0 } }
            animate(duration: halfDuration, completion: fadeOut, animations: fadeIn)
            animate(duration: fullDuration, completion: remove, animations: grow)
            window.addSubview(imageView)
        }

        if !post.loved {
            let footerCell = collectionView.cellForItem(at: footerPath) as? StreamFooterCell
            postbarController?.lovesButtonTapped(footerCell, indexPath: footerPath)
        }
    }

    func cellLongPressed(cell: UICollectionViewCell) {
        guard
            let indexPath = collectionView.indexPath(for: cell),
            let currentUser = currentUser
        else { return }

        if let post = dataSource.postForIndexPath(indexPath),
            currentUser.isOwn(post: post)
        {
            let responder = target(forAction: #selector(CreatePostResponder.editPost(_:fromController:)), withSender: self) as? CreatePostResponder
            responder?.editPost(post, fromController: self)
        }
        else if let comment = dataSource.commentForIndexPath(indexPath),
            currentUser.isOwn(comment: comment)
        {
            let responder = target(forAction: #selector(CreatePostResponder.editComment(_:fromController:)), withSender: self) as? CreatePostResponder
            responder?.editComment(comment, fromController: self)
        }
    }
}

// MARK: StreamViewController: StreamImageCellResponder
extension StreamViewController: StreamImageCellResponder {
    func imageTapped(imageView: FLAnimatedImageView, cell: StreamImageCell) {
        let indexPath = collectionView.indexPath(for: cell)
        let post = indexPath.flatMap(dataSource.postForIndexPath)
        let imageAsset = indexPath.flatMap(dataSource.imageAssetForIndexPath)

        if streamKind.isGridView || cell.isGif {
            if let post = post {
                let responder = target(forAction: #selector(PostTappedResponder.postTapped(_:)), withSender: self) as? PostTappedResponder
                responder?.postTapped(post)
            }
        }
        else if let imageViewer = imageViewer {
            imageViewer.imageTapped(imageView, imageURL: cell.presentedImageUrl)
            if let post = post,
                    let asset = imageAsset {
                Tracker.shared.viewedImage(asset, post: post)
            }
        }
    }
}

// MARK: StreamViewController: Open category
extension StreamViewController {

    func categoryTapped(_ category: Category) {
        showCategoryViewController(slug: category.slug, name: category.name)
    }

    func showCategoryViewController(slug: String, name: String) {
        Tracker.shared.categoryOpened(slug)
        let vc = CategoryViewController(slug: slug, name: name)
        vc.currentUser = currentUser
        navigationController?.pushViewController(vc, animated: true)
    }
}

// MARK: StreamViewController: CategoryResponder
extension StreamViewController: CategoryResponder {

    func categoryCellTapped(cell: UICollectionViewCell) {
        guard
            let indexPath = collectionView.indexPath(for: cell),
            let post = dataSource.jsonableForIndexPath(indexPath) as? Post,
            let category = post.category
        else { return }

        categoryTapped(category)
    }
}


// MARK: StreamViewController: UserResponder
extension StreamViewController: UserResponder {

    func userTappedText(cell: UICollectionViewCell) {
        guard streamKind.tappingTextOpensDetail,
            let indexPath = collectionView.indexPath(for: cell)
        else { return }

        collectionView(collectionView, didSelectItemAt: indexPath)
    }

    func userTapped(user: User) {
        let responder = target(forAction: #selector(UserTappedResponder.userTapped(_:)), withSender: self) as? UserTappedResponder
        responder?.userTapped(user)
    }

    func userTappedAuthor(cell: UICollectionViewCell) {
        guard
            let indexPath = collectionView.indexPath(for: cell),
            let user = dataSource.userForIndexPath(indexPath)
        else { return }

        userTapped(user: user)
    }

    func userTappedReposter(cell: UICollectionViewCell) {
        guard
            let indexPath = collectionView.indexPath(for: cell),
            let reposter = dataSource.reposterForIndexPath(indexPath)
        else { return }

        userTapped(user: reposter)
    }
}

// MARK: StreamViewController: WebLinkResponder
extension StreamViewController: WebLinkResponder {

    func webLinkTapped(path: String, type: ElloURIWrapper, data: String) {
        guard
            let parentController = parent as? HasAppController,
            let appViewController = parentController.appViewController
        else { return }

        appViewController.navigateToURI(path: path, type: type.uri, data: data)
    }

    fileprivate func selectTab(_ tab: ElloTab) {
        elloTabBarController?.selectedTab = tab
    }
}

// MARK: StreamViewController: AnnouncementCellResponder
extension StreamViewController: AnnouncementCellResponder {

    func markAnnouncementAsRead(cell: UICollectionViewCell) {
        guard
            let indexPath = collectionView.indexPath(for: cell),
            let announcement = dataSource.jsonableForIndexPath(indexPath) as? Announcement
        else { return }

        let responder = target(forAction: #selector(AnnouncementResponder.markAnnouncementAsRead(announcement:) ), withSender: self) as? AnnouncementResponder
        responder?.markAnnouncementAsRead(announcement: announcement)
    }
}

// MARK: StreamViewController: UICollectionViewDelegate
extension StreamViewController: UICollectionViewDelegate {

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let cell = cell as? DismissableCell {
            cell.didEndDisplay()
        }
    }

    func collectionView(_ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath) {
        guard
            let tappedCell = collectionView.cellForItem(at: indexPath),
            let item = dataSource.visibleStreamCellItem(at: indexPath),
            let paths = collectionView.indexPathsForSelectedItems,
            tappedCell is CategoryCardCell && item.type == .selectableCategoryCard
        else { return }

        let selection = paths.flatMap { dataSource.jsonableForIndexPath($0) as? Category }

        let responder = target(forAction: #selector(SelectedCategoryResponder.categoriesSelectionChanged(selection:)), withSender: self) as? SelectedCategoryResponder
        responder?.categoriesSelectionChanged(selection: selection)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tappedCell = collectionView.cellForItem(at: indexPath)

        var keepSelected = false
        if tappedCell is StreamToggleCell {
            dataSource.toggleCollapsedForIndexPath(indexPath)
            reloadCells(now: true)
        }
        else if tappedCell is UserListItemCell {
            if let user = dataSource.userForIndexPath(indexPath) {
                userTapped(user: user)
            }
        }
        else if tappedCell is StreamSeeMoreCommentsCell {
            if let lastComment = dataSource.commentForIndexPath(indexPath),
                let post = lastComment.loadedFromPost
            {
                let responder = target(forAction: #selector(PostTappedResponder.postTapped(_:scrollToComment:)), withSender: self) as? PostTappedResponder
                responder?.postTapped(post, scrollToComment: lastComment)
            }
        }
        else if let post = dataSource.postForIndexPath(indexPath) {
            let responder = target(forAction: #selector(PostTappedResponder.postTapped(_:)), withSender: self) as? PostTappedResponder
            responder?.postTapped(post)
        }
        else if let notification = dataSource.jsonableForIndexPath(indexPath) as? Notification,
            let postId = notification.postId
        {
            let responder = target(forAction: #selector(PostTappedResponder.postTapped(postId:)), withSender: self) as? PostTappedResponder
            responder?.postTapped(postId: postId)
        }
        else if let notification = dataSource.jsonableForIndexPath(indexPath) as? Notification,
            let user = notification.subject as? User
        {
            userTapped(user: user)
        }
        else if let announcement = dataSource.jsonableForIndexPath(indexPath) as? Announcement,
            let callToAction = announcement.ctaURL
        {
            Tracker.shared.announcementOpened(announcement)
            let request = URLRequest(url: callToAction)
            ElloWebViewHelper.handle(request: request, origin: self)
        }
        else if let comment = dataSource.commentForIndexPath(indexPath) {
            let responder = target(forAction: #selector(CreatePostResponder.createComment(_:text:fromController:)), withSender: self) as? CreatePostResponder
            responder?.createComment(comment.loadedFromPostId, text: nil, fromController: self)
        }
        else if let item = dataSource.visibleStreamCellItem(at: indexPath),
            let category = dataSource.jsonableForIndexPath(indexPath) as? Category
        {
            if item.type == .selectableCategoryCard {
                keepSelected = true
                let paths = collectionView.indexPathsForSelectedItems
                let selection = paths?.flatMap { dataSource.jsonableForIndexPath($0) as? Category }

                let responder = target(forAction: #selector(SelectedCategoryResponder.categoriesSelectionChanged(selection:)), withSender: self) as? SelectedCategoryResponder
                responder?.categoriesSelectionChanged(selection: selection ?? [Category]())
            }
            else {
                showCategoryViewController(slug: category.slug, name: category.name)
            }
        }

        if !keepSelected {
            collectionView.deselectItem(at: indexPath, animated: false)
        }
    }

    func collectionView(_ collectionView: UICollectionView,
        shouldSelectItemAt indexPath: IndexPath) -> Bool {
            guard
                let cellItemType = dataSource.visibleStreamCellItem(at: indexPath)?.type
            else { return false }

            return cellItemType.selectable
    }
}

// MARK: StreamViewController: UIScrollViewDelegate
extension StreamViewController: UIScrollViewDelegate {

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        streamViewDelegate?.streamViewDidScroll(scrollView: scrollView)
        if !noResultsLabel.isHidden {
            noResultsTopConstraint.constant = -scrollView.contentOffset.y + defaultNoResultsTopConstant
            self.view.layoutIfNeeded()
        }

        if scrollToPaginateGuard {
            self.loadNextPage(scrollView: scrollView)
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollToPaginateGuard = true
        streamViewDelegate?.streamViewWillBeginDragging(scrollView: scrollView)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate: Bool) {
        streamViewDelegate?.streamViewDidEndDragging(scrollView: scrollView, willDecelerate: willDecelerate)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollToPaginateGuard = false
    }

    fileprivate func loadNextPage(scrollView: UIScrollView) {
        guard
            pagingEnabled &&
            scrollView.contentOffset.y + (self.view.frame.height * 1.666)
            > scrollView.contentSize.height
        else { return }

        guard
            !allOlderPagesLoaded &&
            responseConfig?.totalPagesRemaining != "0"
        else { return }

        guard
            let nextQueryItems = responseConfig?.nextQueryItems
        else { return }

        guard let lastCellItem = dataSource.visibleCellItems.last, lastCellItem.type != .streamLoading
        else { return }

        let placeholderType = lastCellItem.placeholderType
        appendStreamCellItems([StreamCellItem(type: .streamLoading)])

        scrollToPaginateGuard = false

        let scrollAPI = ElloAPI.infiniteScroll(queryItems: nextQueryItems) { return self.streamKind.endpoint }
        streamService.loadStream(
            endpoint: scrollAPI,
            streamKind: streamKind,
            success: {
                (jsonables, responseConfig) in
                self.scrollLoaded(jsonables: jsonables, placeholderType: placeholderType)
                self.responseConfig = responseConfig
            },
            failure: { (error, statusCode) in
                print("failed to load stream (reason: \(error))")
                self.scrollLoaded()
            },
            noContent: {
                self.allOlderPagesLoaded = true
                self.scrollLoaded()
            })
    }

    fileprivate func scrollLoaded(jsonables: [JSONAble] = [], placeholderType: StreamCellType.PlaceholderType? = nil) {
        guard
            let lastIndexPath = collectionView.lastIndexPathForSection(0)
        else { return }

        if jsonables.count > 0 {
            if let controller = parent as? BaseElloViewController {
                Tracker.shared.screenAppeared(controller)
            }

            let items = StreamCellItemParser().parse(jsonables, streamKind: streamKind, currentUser: currentUser)
            for item in items {
                item.placeholderType = placeholderType
            }
            insertUnsizedCellItems(items, startingIndexPath: lastIndexPath) {
                self.removeLoadingCell()
                self.doneLoading()
            }
        }
        else {
            removeLoadingCell()
            self.doneLoading()
        }
    }

    fileprivate func removeLoadingCell() {
        let lastIndexPath = IndexPath(item: dataSource.visibleCellItems.count - 1, section: 0)
        guard
            dataSource.visibleCellItems[lastIndexPath.row].type == .streamLoading
        else { return }

        dataSource.removeItemsAtIndexPaths([lastIndexPath])
        reloadCells(now: true)
    }
}
