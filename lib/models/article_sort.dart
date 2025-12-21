enum ArticleSortOption {
  dateDesc, // Newest first (default)
  dateAsc,  // Oldest first
  titleAsc,
  titleDesc,
  feedAsc,
  feedDesc,
  authorAsc,
  authorDesc,
}

extension ArticleSortOptionExtension on ArticleSortOption {
  String get displayName {
    switch (this) {
      case ArticleSortOption.dateDesc:
        return 'Date (Newest)';
      case ArticleSortOption.dateAsc:
        return 'Date (Oldest)';
      case ArticleSortOption.titleAsc:
        return 'Title (A-Z)';
      case ArticleSortOption.titleDesc:
        return 'Title (Z-A)';
      case ArticleSortOption.feedAsc:
        return 'Feed (A-Z)';
      case ArticleSortOption.feedDesc:
        return 'Feed (Z-A)';
      case ArticleSortOption.authorAsc:
        return 'Author (A-Z)';
      case ArticleSortOption.authorDesc:
        return 'Author (Z-A)';
    }
  }
}





