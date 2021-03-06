////
///  AppDefaults.swift
//

extension UserDefaults {
    func resetOnLogout() {
        let groupDefaultResetKeys = [
            "ElloImageUploadQuality",
            StreamKind.notifications(category: nil).lastViewedCreatedAtKey,
            StreamKind.announcements.lastViewedCreatedAtKey,
            StreamKind.following.lastViewedCreatedAtKey,
        ]
        for key in groupDefaultResetKeys {
            self[key] = nil
        }
    }
}
