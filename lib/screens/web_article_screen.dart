import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../widgets/platform_app_bar.dart';

class WebArticleScreen extends StatefulWidget {
  final String title;
  final String url;

  const WebArticleScreen({
    super.key,
    required this.title,
    required this.url,
  });

  @override
  State<WebArticleScreen> createState() => _WebArticleScreenState();
}

class _WebArticleScreenState extends State<WebArticleScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(widget.url));
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


