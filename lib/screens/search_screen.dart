import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/article.dart';
import '../models/feed.dart';
import '../database/article_dao.dart';
import '../database/feed_dao.dart';
import '../providers/app_provider.dart';
import '../services/account_service.dart';
import '../services/search_history_service.dart';
import '../utils/reading_time.dart';
import 'article_reader_screen.dart';
import '../utils/rtl_helper.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final SearchHistoryService _searchHistoryService = SearchHistoryService();
  List<Article> _searchResults = [];
  List<String> _searchHistory = [];
  bool _isSearching = false;
  bool _showHistory = true;
  int? _accountId;
  
  // Filters
  String? _selectedFeedId;
  List<Feed> _feeds = [];
  DateTime? _startDate;
  DateTime? _endDate;
  bool? _starredFilter;
  bool? _unreadFilter;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
    _loadSearchHistory();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeeds() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) return;
      
      setState(() => _accountId = account.id);
      
      final feedDao = ref.read(feedDaoProvider);
      final feeds = await feedDao.getAll(account.id!);
      setState(() => _feeds = feeds);
    } catch (e) {
      // Error loading feeds
    }
  }

  Future<void> _loadSearchHistory() async {
    try {
      final account = await ref.read(accountServiceProvider).getCurrentAccount();
      if (account == null) return;
      
      final history = await _searchHistoryService.getSearchHistory(account.id!);
      setState(() => _searchHistory = history);
    } catch (e) {
      // Error loading history
    }
  }

  Future<void> _performSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showHistory = true;
      });
      return;
    }

    if (_accountId == null) return;

    setState(() {
      _isSearching = true;
      _showHistory = false;
    });

    try {
      // Save to search history
      await _searchHistoryService.addSearchQuery(_accountId!, query);
      await _loadSearchHistory();

      final articleDao = ref.read(articleDaoProvider);
      final results = await articleDao.search(
        accountId: _accountId!,
        query: query,
        feedId: _selectedFeedId,
        startDate: _startDate,
        endDate: _endDate,
        starred: _starredFilter,
        unread: _unreadFilter,
      );

      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() => _isSearching = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching: $e')),
        );
      }
    }
  }

  void _showFilters() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _FiltersSheet(
        feeds: _feeds,
        selectedFeedId: _selectedFeedId,
        startDate: _startDate,
        endDate: _endDate,
        starredFilter: _starredFilter,
        unreadFilter: _unreadFilter,
        onFiltersChanged: (feedId, startDate, endDate, starred, unread) {
          setState(() {
            _selectedFeedId = feedId;
            _startDate = startDate;
            _endDate = endDate;
            _starredFilter = starred;
            _unreadFilter = unread;
          });
          if (_searchController.text.isNotEmpty) {
            _performSearch(_searchController.text);
          }
        },
      ),
    );
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedFeedId != null) count++;
    if (_startDate != null) count++;
    if (_endDate != null) count++;
    if (_starredFilter != null) count++;
    if (_unreadFilter != null) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search articles...',
            border: InputBorder.none,
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchResults = [];
                        _showHistory = true;
                      });
                    },
                  )
                : null,
          ),
          onSubmitted: _performSearch,
          onChanged: (value) {
            setState(() {});
            if (value.isEmpty) {
              setState(() {
                _searchResults = [];
                _showHistory = true;
              });
            }
          },
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilters,
              ),
              if (_getActiveFilterCount() > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${_getActiveFilterCount()}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _isSearching
          ? const Center(child: CircularProgressIndicator())
          : _showHistory && _searchController.text.isEmpty
              ? _buildSearchHistory()
              : _searchResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No results found',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ],
                      ),
                    )
                  : _buildSearchResults(),
    );
  }

  Widget _buildSearchHistory() {
    if (_searchHistory.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 64,
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'No search history',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (_searchHistory.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                TextButton(
                  onPressed: () async {
                    if (_accountId != null) {
                      await _searchHistoryService.clearSearchHistory(_accountId!);
                      await _loadSearchHistory();
                    }
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        ..._searchHistory.map((query) => ListTile(
              leading: const Icon(Icons.history),
              title: Text(query),
              onTap: () {
                _searchController.text = query;
                _performSearch(query);
              },
              trailing: IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () async {
                  if (_accountId != null) {
                    await _searchHistoryService.removeSearchQuery(_accountId!, query);
                    await _loadSearchHistory();
                  }
                },
              ),
            )),
      ],
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final article = _searchResults[index];
        return _buildArticleCard(article);
      },
    );
  }

  Widget _buildArticleCard(Article article) {
    final readingTime = ReadingTime.calculateAndFormat(
      article.fullContent ?? article.rawDescription,
    );
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        title: Text(
          article.title,
          style: TextStyle(
            fontWeight: article.isUnread ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              article.shortDescription,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (readingTime.isNotEmpty) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 14,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        readingTime,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _formatDate(article.date),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (article.isStarred)
                  Icon(
                    Icons.star,
                    size: 14,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ],
        ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ArticleReaderScreen(article: article),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Ensure both dates are in local timezone for accurate comparison
    final now = DateTime.now();
    final localDate = date.isUtc ? date.toLocal() : date;
    final difference = now.difference(localDate);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

class _FiltersSheet extends StatefulWidget {
  final List<Feed> feeds;
  final String? selectedFeedId;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool? starredFilter;
  final bool? unreadFilter;
  final Function(String?, DateTime?, DateTime?, bool?, bool?) onFiltersChanged;

  const _FiltersSheet({
    required this.feeds,
    required this.selectedFeedId,
    required this.startDate,
    required this.endDate,
    required this.starredFilter,
    required this.unreadFilter,
    required this.onFiltersChanged,
  });

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _selectedFeedId;
  late DateTime? _startDate;
  late DateTime? _endDate;
  late bool? _starredFilter;
  late bool? _unreadFilter;

  @override
  void initState() {
    super.initState();
    _selectedFeedId = widget.selectedFeedId;
    _startDate = widget.startDate;
    _endDate = widget.endDate;
    _starredFilter = widget.starredFilter;
    _unreadFilter = widget.unreadFilter;
  }

  Future<void> _selectDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? (_startDate ?? DateTime.now()) : (_endDate ?? DateTime.now()),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Filters',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _selectedFeedId = null;
                      _startDate = null;
                      _endDate = null;
                      _starredFilter = null;
                      _unreadFilter = null;
                    });
                  },
                  child: const Text('Clear All'),
                ),
              ],
            ),
          ),
          ListTile(
            title: const Text('Feed'),
            subtitle: _selectedFeedId != null
                ? Text(widget.feeds.firstWhere((f) => f.id == _selectedFeedId).name)
                : const Text('All feeds'),
            trailing: DropdownButton<String>(
              value: _selectedFeedId,
              hint: const Text('All'),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('All feeds'),
                ),
                ...widget.feeds.map((feed) => DropdownMenuItem<String>(
                      value: feed.id,
                      child: Text(feed.name),
                    )),
              ],
              onChanged: (value) {
                setState(() => _selectedFeedId = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Start Date'),
            subtitle: Text(_startDate != null
                ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                : 'No start date'),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () => _selectDate(true),
            ),
          ),
          ListTile(
            title: const Text('End Date'),
            subtitle: Text(_endDate != null
                ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                : 'No end date'),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () => _selectDate(false),
            ),
          ),
          ListTile(
            title: const Text('Starred'),
            trailing: DropdownButton<bool?>(
              value: _starredFilter,
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('All')),
                DropdownMenuItem<bool?>(value: true, child: Text('Starred only')),
                DropdownMenuItem<bool?>(value: false, child: Text('Not starred')),
              ],
              onChanged: (value) {
                setState(() => _starredFilter = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Read Status'),
            trailing: DropdownButton<bool?>(
              value: _unreadFilter,
              items: const [
                DropdownMenuItem<bool?>(value: null, child: Text('All')),
                DropdownMenuItem<bool?>(value: true, child: Text('Unread only')),
                DropdownMenuItem<bool?>(value: false, child: Text('Read only')),
              ],
              onChanged: (value) {
                setState(() => _unreadFilter = value);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  widget.onFiltersChanged(
                    _selectedFeedId,
                    _startDate,
                    _endDate,
                    _starredFilter,
                    _unreadFilter,
                  );
                  Navigator.pop(context);
                },
                child: const Text('Apply Filters'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

