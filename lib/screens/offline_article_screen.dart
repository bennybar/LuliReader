import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../widgets/platform_app_bar.dart';

class OfflineArticleScreen extends StatefulWidget {
  final String filePath;
  final String title;

  const OfflineArticleScreen({
    super.key,
    required this.filePath,
    required this.title,
  });

  @override
  State<OfflineArticleScreen> createState() => _OfflineArticleScreenState();
}

class _OfflineArticleScreenState extends State<OfflineArticleScreen> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..loadFile(widget.filePath);
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


