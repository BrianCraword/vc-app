import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:forum_kit/views/widgets/themed_web_view.dart';
import 'package:forumcopilot_sdk/forumcopilot_sdk.dart';

import '../services/forum_web_entry.dart';

/// A forum page the app does not render natively, opened as the member who
/// is signed into the app.
///
/// Matchmaking, the Feed's own views, the research library and anything a
/// theme component draws are web pages. This opens one of them in a web view
/// that holds the member's session, so they see their own account rather
/// than a signed-out page.
///
/// The first time, Discourse's own confirmation page appears and the member
/// taps once to connect their account. The app does not submit that form for
/// them: it is the step where a human sees whose account is about to be
/// used. Afterwards the session cookie lives in the web view's jar, so every
/// later page opens straight away — the tap is once per install, not once
/// per page.
class ForumPageWebView extends StatefulWidget {
  const ForumPageWebView({
    super.key,
    required this.siteContext,
    required this.path,
    required this.title,
  });

  /// The forum's path, with or without its leading slash — `/matchmaking`.
  final String path;

  /// Shown in the app bar. Supplied by the caller, which knows what it is
  /// opening; this widget adds no strings of its own.
  final String title;

  final SiteContext siteContext;

  @override
  State<ForumPageWebView> createState() => _ForumPageWebViewState();
}

class _ForumPageWebViewState extends State<ForumPageWebView> {
  late final ForumWebEntry _entry =
      ForumWebEntry(siteContext: widget.siteContext);
  late final Future<ForumWebStart> _start = _entry.start(widget.path);

  /// One jump only. Discourse lands a member on the forum root after the
  /// confirmation, and they are free to navigate back to it afterwards —
  /// without this, doing so would throw them at the target page again.
  bool _jumped = false;

  void _onNavigated(
    ForumWebStart start,
    InAppWebViewController controller,
    WebUri? url,
  ) {
    if (_jumped || !start.viaConfirmation || url == null) return;
    if (!_entry.isPostConfirmationLanding(url)) return;

    _jumped = true;
    controller.loadUrl(
      urlRequest: URLRequest(url: WebUri(start.target.toString())),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        // As in a browser tab opened from the app, matching
        // InAppWebViewPage: ✕ closes the page from wherever it has got to,
        // and Back goes back a page first.
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: FutureBuilder<ForumWebStart>(
        future: _start,
        builder: (context, snapshot) {
          final start = snapshot.data;
          if (start == null) {
            // Minting is a round trip to the forum. The same cover
            // ThemedWebView uses, so the hand-off is not a visible change.
            return ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return ThemedWebView(
            url: start.url.toString(),
            backGoesThroughHistory: true,
            onNavigated: (controller, url) =>
                _onNavigated(start, controller, url),
          );
        },
      ),
    );
  }
}
