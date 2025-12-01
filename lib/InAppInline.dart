import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Model class containing WebView information
class InAppInlineWebViewInfo {
  /// Loaded URL
  final String? url;

  /// Page title
  final String? title;

  /// Content height (pixels)
  final double? contentHeight;

  /// Content width (pixels)
  final double? contentWidth;

  /// Can go back
  final bool canGoBack;

  /// Can go forward
  final bool canGoForward;

  const InAppInlineWebViewInfo({
    this.url,
    this.title,
    this.contentHeight,
    this.contentWidth,
    this.canGoBack = false,
    this.canGoForward = false,
  });

  factory InAppInlineWebViewInfo.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const InAppInlineWebViewInfo();
    }
    return InAppInlineWebViewInfo(
      url: map['url'] as String?,
      title: map['title'] as String?,
      contentHeight: (map['contentHeight'] as num?)?.toDouble(),
      contentWidth: (map['contentWidth'] as num?)?.toDouble(),
      canGoBack: map['canGoBack'] as bool? ?? false,
      canGoForward: map['canGoForward'] as bool? ?? false,
    );
  }

  @override
  String toString() {
    return 'InAppInlineWebViewInfo(url: $url, title: $title, contentHeight: $contentHeight, contentWidth: $contentWidth, canGoBack: $canGoBack, canGoForward: $canGoForward)';
  }
}

/// InAppInline loading state
enum InAppInlineState {
  /// Loading
  loading,

  /// Successfully loaded
  loaded,

  /// Error occurred
  error,

  /// Content not found
  notFound,
}

/// Model containing InAppInline status
class InAppInlineStatus {
  /// Current state
  final InAppInlineState state;

  /// WebView information (only filled when loaded)
  final InAppInlineWebViewInfo? webViewInfo;

  /// Error message (only filled when error)
  final String? errorMessage;

  const InAppInlineStatus({
    required this.state,
    this.webViewInfo,
    this.errorMessage,
  });

  /// Is it loading?
  bool get isLoading => state == InAppInlineState.loading;

  /// Is it loaded?
  bool get isLoaded => state == InAppInlineState.loaded;

  /// Is there an error?
  bool get isError => state == InAppInlineState.error;

  /// Is content not found?
  bool get isNotFound => state == InAppInlineState.notFound;

  @override
  String toString() {
    return 'InAppInlineStatus(state: $state, webViewInfo: $webViewInfo, errorMessage: $errorMessage)';
  }
}

/// InAppInline builder callback type
///
/// [status] - Current loading state and information
/// [view] - WebView widget (return this when loaded)
typedef InAppInlineBuilder = Widget Function(
    InAppInlineStatus status, Widget view);

/// InAppInline widget - Stays hidden until WebView content is loaded
class InAppInline extends StatefulWidget {
  final String propertyId;
  final String? screenName;
  final HashMap<String, String>? customParams;

  /// Builder function called on state changes
  ///
  /// This function is called on every state change:
  /// - `loading`: Loading - return loading widget
  /// - `loaded`: Loaded - return view
  /// - `error`: Error - return error widget or view
  /// - `notFound`: Not found - return SizedBox.shrink() to hide
  ///
  /// ```dart
  /// InAppInline(
  ///   propertyId: "banner",
  ///   builder: (status, view) {
  ///     if (status.isLoading) return CircularProgressIndicator();
  ///     if (status.isNotFound) return SizedBox.shrink();
  ///     if (status.isError) return Text('Error: ${status.errorMessage}');
  ///     return view; // WebView'ı göster
  ///   },
  /// )
  /// ```
  final InAppInlineBuilder builder;

  /// Content loading timeout duration (default: 10 seconds)
  final Duration timeout;

  const InAppInline({
    Key? key,
    required this.propertyId,
    required this.builder,
    this.screenName,
    this.customParams,
    this.timeout = const Duration(seconds: 10),
  }) : super(key: key);

  @override
  State<InAppInline> createState() => _InAppInlineState();
}

class _InAppInlineState extends State<InAppInline> {
  InAppInlineStatus _status =
      const InAppInlineStatus(state: InAppInlineState.loading);
  MethodChannel? _channel;
  Timer? _timeoutTimer;

  /// Current status
  InAppInlineStatus get status => _status;

  @override
  void initState() {
    super.initState();
    print('[InAppInline] initState called - propertyId: ${widget.propertyId}');
    _startTimeoutTimer();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _startTimeoutTimer() {
    print('[InAppInline] Starting timeout timer: ${widget.timeout}');
    _timeoutTimer = Timer(widget.timeout, () {
      print(
          '[InAppInline] Timeout reached! mounted: $mounted, isLoading: ${_status.isLoading}');
      if (mounted && _status.isLoading) {
        print(
            '[InAppInline] Timeout: Content not loaded, setting status to notFound');
        _updateStatus(
            const InAppInlineStatus(state: InAppInlineState.notFound));
      }
    });
  }

  void _updateStatus(InAppInlineStatus newStatus) {
    if (!mounted) return;
    setState(() {
      _status = newStatus;
    });
  }

  void _onPlatformViewCreated(int viewId) {
    print('[InAppInline] onPlatformViewCreated called! viewId: $viewId');
    print(
        '[InAppInline] Setting up MethodChannel: plugins.dengage/inappinline_$viewId');
    _channel = MethodChannel('plugins.dengage/inappinline_$viewId');
    _channel?.setMethodCallHandler(_handleMethodCall);
    print('[InAppInline] MethodChannel handler set successfully');
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    print('[InAppInline] Received method call from native: ${call.method}');
    print('[InAppInline] Arguments: ${call.arguments}');
    
    switch (call.method) {
      case 'onDebugLog':
        // Native debug logs
        final message = call.arguments['message'] as String?;
        if (message != null) {
          print('[iOS Native] $message');
        }
        break;
      case 'onContentLoaded':
        _timeoutTimer?.cancel();
        if (mounted) {
          final info = InAppInlineWebViewInfo.fromMap(
            call.arguments as Map<dynamic, dynamic>?,
          );
          _updateStatus(InAppInlineStatus(
            state: InAppInlineState.loaded,
            webViewInfo: info,
          ));
        }
        break;
      case 'onContentError':
        _timeoutTimer?.cancel();
        if (mounted) {
          final args = call.arguments as Map<dynamic, dynamic>?;
          final errorMessage = args?['description'] as String?;
          _updateStatus(InAppInlineStatus(
            state: InAppInlineState.error,
            errorMessage: errorMessage,
          ));
        }
        break;
      case 'onContentNotFound':
        _timeoutTimer?.cancel();
        if (mounted) {
          _updateStatus(
              const InAppInlineStatus(state: InAppInlineState.notFound));
        }
        break;
    }
  }

  Map<String, dynamic> get _creationParams => {
        "propertyId": widget.propertyId,
        "screenName": widget.screenName,
        "customParams": widget.customParams,
      };

  Widget _buildPlatformView() {
    print('[InAppInline] _buildPlatformView called for $defaultTargetPlatform');
    print('[InAppInline] creationParams: $_creationParams');
    
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        print('[InAppInline] Creating AndroidView...');
        return AndroidView(
          viewType: 'plugins.dengage/inappinline',
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
        print('[InAppInline] Creating UiKitView...');
        return UiKitView(
          viewType: 'plugins.dengage/inappinline',
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      default:
        return Text(
            '$defaultTargetPlatform is not yet supported by the web_view plugin');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('[InAppInline] build called - status: ${_status.state}');

    // Always build platform view (required for iOS UiKitView to initialize)
    final platformView = _buildPlatformView();

    // Keep invisible until loaded (native side also animates alpha)
    final view = Opacity(
      opacity: _status.isLoaded ? 1.0 : 0.0,
      child: platformView,
    );

    // Call builder
    print('[InAppInline] Calling builder with status: ${_status.state}');
    return widget.builder(_status, view);
  }
}
