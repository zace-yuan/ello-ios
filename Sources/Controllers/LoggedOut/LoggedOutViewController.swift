////
///  LoggedOutViewController.swift
//

import SnapKit


protocol BottomBarController: class {
    var navigationBarsVisible: Bool { get }
    var bottomBarVisible: Bool { get }
    var bottomBarHeight: CGFloat { get }
    var bottomBarView: UIView { get }
    func setNavigationBarsVisible(_ visible: Bool, animated: Bool)
}


class LoggedOutViewController: BaseElloViewController, BottomBarController {
    var navigationBarsVisible: Bool = true
    let bottomBarVisible: Bool = true
    var bottomBarHeight: CGFloat { return screen.bottomBarHeight }
    var bottomBarView: UIView { return screen.bottomBarView }

    var mockScreen: LoggedOutScreenProtocol?
    var screen: LoggedOutScreenProtocol { return mockScreen ?? (self.view as! LoggedOutScreenProtocol) }

    fileprivate var userActionAttemptedObserver: NotificationObserver?

    func setNavigationBarsVisible(_ visible: Bool, animated: Bool) {
        navigationBarsVisible = visible
    }

    override func addChildViewController(_ childController: UIViewController) {
        super.addChildViewController(childController)
        screen.setControllerView(childController.view)
    }

    override func loadView() {
        let screen = LoggedOutScreen()
        screen.delegate = self
        self.view = screen
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        setupNotificationObservers()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        removeNotificationObservers()
    }
}

extension LoggedOutViewController {

    func setupNotificationObservers() {
        userActionAttemptedObserver = NotificationObserver(notification: LoggedOutNotifications.userActionAttempted) { [weak self] action in
            switch action {
            case .relationshipChange:
                Tracker.shared.loggedOutRelationshipAction()
            case .postTool:
                Tracker.shared.loggedOutPostTool()
            }
            self?.screen.showJoinText()
        }
    }

    func removeNotificationObservers() {
        userActionAttemptedObserver?.removeObserver()
    }

}

extension LoggedOutViewController: LoggedOutProtocol {
    func showLoginScreen() {
        appViewController?.showLoginScreen()
    }

    func showJoinScreen() {
        appViewController?.showJoinScreen()
    }
}
