import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/platform_app_bar.dart';

class ReaderArticleScreen extends StatefulWidget {
  final String title;
  final String html;

  const ReaderArticleScreen({
    super.key,
    required this.title,
    required this.html,
  });

  @override
  State<ReaderArticleScreen> createState() => _ReaderArticleScreenState();
}

class _ReaderArticleScreenState extends State<ReaderArticleScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadHtmlString(widget.html);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PlatformAppBar(
        title: widget.title,
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}


