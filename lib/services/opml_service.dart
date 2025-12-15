import 'dart:convert';
import 'package:xml/xml.dart' as xml;
import '../models/feed.dart';
import '../models/group.dart';
import '../database/feed_dao.dart';
import '../database/group_dao.dart';
import '../services/account_service.dart';
import '../services/local_rss_service.dart';
import 'package:uuid/uuid.dart';

class OpmlService {
  final FeedDao _feedDao;
  final GroupDao _groupDao;
  final AccountService _accountService;
  final LocalRssService _rssService;

  OpmlService(
    this._feedDao,
    this._groupDao,
    this._accountService,
    this._rssService,
  );

  /// Import OPML file from string
  Future<void> importFromString(String opmlContent, int accountId) async {
    final document = xml.XmlDocument.parse(opmlContent);
    final body = document.findAllElements('body').firstOrNull;
    if (body == null) throw Exception('Invalid OPML: no body found');

    final defaultGroupId = _groupDao.getDefaultGroupId(accountId);
    var defaultGroup = await _groupDao.getById(defaultGroupId);
    if (defaultGroup == null) {
      // Create default group if it doesn't exist
      defaultGroup = Group(
        id: defaultGroupId,
        name: 'Default',
        accountId: accountId,
      );
      await _groupDao.insert(defaultGroup);
    }

    final outlines = body.findAllElements('outline');
    final groupsToCreate = <Group>[];
    final feedsToCreate = <Feed>[];

    for (final outline in outlines) {
      await _processOutline(
        outline,
        accountId,
        defaultGroup,
        groupsToCreate,
        feedsToCreate,
      );
    }

    // Create groups
    for (final group in groupsToCreate) {
      await _groupDao.insert(group);
    }

      // Create feeds (skip duplicates)
      final newFeeds = <Feed>[];
      for (final feed in feedsToCreate) {
        if (!await _feedDao.isFeedExist(feed.url)) {
          await _feedDao.insert(feed);
          newFeeds.add(feed);
        }
      }
      
      // Auto-sync new feeds after import
      if (newFeeds.isNotEmpty) {
        try {
          await _rssService.sync(accountId);
        } catch (e) {
          print('Error auto-syncing after OPML import: $e');
          // Don't throw - import was successful, sync can happen later
        }
      }
  }

  Future<void> _processOutline(
    xml.XmlElement outline,
    int accountId,
    Group defaultGroup,
    List<Group> groupsToCreate,
    List<Feed> feedsToCreate,
  ) async {
    final subOutlines = outline.findElements('outline');
    final xmlUrl = outline.getAttribute('xmlUrl') ?? outline.getAttribute('url');
    final title = outline.getAttribute('title') ?? outline.getAttribute('text') ?? '';

    // If it has sub-outlines, it's a group
    if (subOutlines.isNotEmpty) {
      final isDefault = outline.getAttribute('isDefault') == 'true';
      Group targetGroup;

      if (isDefault) {
        targetGroup = defaultGroup;
      } else {
        // Create new group
        final groupId = '$accountId\$${const Uuid().v4()}';
        targetGroup = Group(
          id: groupId,
          name: title.isNotEmpty ? title : 'Untitled Group',
          accountId: accountId,
        );
        groupsToCreate.add(targetGroup);
      }

      // Process sub-outlines (feeds)
      for (final subOutline in subOutlines) {
        final feed = _createFeedFromOutline(subOutline, accountId, targetGroup.id);
        if (feed != null) {
          feedsToCreate.add(feed);
        }
      }
    } else if (xmlUrl != null && xmlUrl.isNotEmpty) {
      // It's a feed at root level
      final feed = _createFeedFromOutline(outline, accountId, defaultGroup.id);
      if (feed != null) {
        feedsToCreate.add(feed);
      }
    } else if (title.isNotEmpty) {
      // It's an empty group
      final isDefault = outline.getAttribute('isDefault') == 'true';
      if (!isDefault) {
        final groupId = '$accountId\$${const Uuid().v4()}';
        final group = Group(
          id: groupId,
          name: title,
          accountId: accountId,
        );
        groupsToCreate.add(group);
      }
    }
  }

  Feed? _createFeedFromOutline(xml.XmlElement outline, int accountId, String groupId) {
    final xmlUrl = outline.getAttribute('xmlUrl') ?? outline.getAttribute('url');
    if (xmlUrl == null || xmlUrl.isEmpty) return null;

    final title = outline.getAttribute('title') ?? 
                  outline.getAttribute('text') ?? 
                  'Untitled Feed';
    
    final isNotification = outline.getAttribute('isNotification') == 'true';
    final isFullContent = outline.getAttribute('isFullContent') == 'true';
    final isBrowser = outline.getAttribute('isBrowser') == 'true';

    return Feed(
      id: '$accountId\$${const Uuid().v4()}',
      name: title,
      url: xmlUrl,
      groupId: groupId,
      accountId: accountId,
      isNotification: isNotification,
      isFullContent: isFullContent,
      isBrowser: isBrowser,
    );
  }

  /// Export OPML file as string
  Future<String> exportToString(int accountId, {bool attachInfo = false}) async {
    final account = await _accountService.getById(accountId);
    if (account == null) throw Exception('Account not found');

    final groupsWithFeeds = await _groupDao.getAllWithFeeds(accountId);
    final defaultGroupId = _groupDao.getDefaultGroupId(accountId);
    final defaultGroup = await _groupDao.getById(defaultGroupId);

    final builder = xml.XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      builder.element('head', nest: () {
        builder.element('title', nest: account.name);
        builder.element('dateCreated', nest: DateTime.now().toIso8601String());
      });
      builder.element('body', nest: () {
        for (final groupWithFeed in groupsWithFeeds) {
          final isDefault = groupWithFeed.group.id == defaultGroup?.id;
          
          if (groupWithFeed.feeds.isEmpty && !isDefault) {
            // Empty group
            builder.element('outline', attributes: {
              'text': groupWithFeed.group.name,
              'title': groupWithFeed.group.name,
              if (attachInfo) 'isDefault': isDefault.toString(),
            });
          } else if (groupWithFeed.feeds.isNotEmpty) {
            // Group with feeds
            builder.element('outline', attributes: {
              'text': groupWithFeed.group.name,
              'title': groupWithFeed.group.name,
              if (attachInfo) 'isDefault': isDefault.toString(),
            }, nest: () {
              for (final feed in groupWithFeed.feeds) {
                final feedObj = feed as Feed;
                builder.element('outline', attributes: {
                  'text': feedObj.name,
                  'title': feedObj.name,
                  'xmlUrl': feedObj.url,
                  'htmlUrl': feedObj.url,
                  if (attachInfo) 'isNotification': feedObj.isNotification.toString(),
                  if (attachInfo) 'isFullContent': feedObj.isFullContent.toString(),
                  if (attachInfo) 'isBrowser': feedObj.isBrowser.toString(),
                });
              }
            });
          }
        }
      });
    });

    final document = builder.buildDocument();
    return document.toXmlString(pretty: true);
  }
}

