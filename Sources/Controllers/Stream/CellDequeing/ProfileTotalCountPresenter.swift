////
///  ProfileTotalCountPresenter.swift
//

import Foundation


public struct ProfileTotalCountPresenter {

    public static func configure(
        view: ProfileTotalCountView,
        user: User,
        currentUser: User?)
    {
        view.count = user.formattedTotalCount()
        view.badgeButton.hidden = !(user.categories?.count > 0)
    }
}
