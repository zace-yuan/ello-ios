////
///  CategoryCellPresenter.swift
//

public struct CategoryCellPresenter {

    static func configure(
        cell: UICollectionViewCell,
        streamCellItem: StreamCellItem,
        streamKind: StreamKind,
        indexPath: NSIndexPath,
        currentUser: User?)
    {
        if let cell = cell as? CategoryCell,
            category = streamCellItem.jsonable as? Category
        {
            cell.title = category.name
            cell.highlight = category.level == .Meta ? .Gray : .White
        }
    }

}
