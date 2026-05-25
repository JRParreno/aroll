import 'package:equatable/equatable.dart';

/// Generic paginated API response wrapper.
class PageData<T> extends Equatable {
  const PageData({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.totalItems,
    this.size = 10,
  });

  final List<T> items;
  final int page;
  final int size;
  final int totalPages;
  final int totalItems;

  bool get hasMore => page < totalPages;

  PageData<T> append(PageData<T> next) {
    return PageData<T>(
      items: [...items, ...next.items],
      page: next.page,
      size: next.size,
      totalPages: next.totalPages,
      totalItems: next.totalItems,
    );
  }

  @override
  List<Object?> get props => [items, page, size, totalPages, totalItems];
}
