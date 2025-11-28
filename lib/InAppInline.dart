import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// WebView bilgilerini içeren model sınıfı
class InAppInlineWebViewInfo {
  /// Yüklenen URL
  final String? url;

  /// Sayfa başlığı
  final String? title;

  /// İçerik yüksekliği (piksel)
  final double? contentHeight;

  /// İçerik genişliği (piksel)
  final double? contentWidth;

  /// Geri gidilebilir mi
  final bool canGoBack;

  /// İleri gidilebilir mi
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

/// InAppInline yükleme durumu
enum InAppInlineState {
  /// Yükleniyor
  loading,

  /// Başarıyla yüklendi
  loaded,

  /// Hata oluştu
  error,

  /// İçerik bulunamadı
  notFound,
}

/// InAppInline durumunu içeren model
class InAppInlineStatus {
  /// Mevcut durum
  final InAppInlineState state;

  /// WebView bilgileri (sadece loaded durumunda dolu)
  final InAppInlineWebViewInfo? webViewInfo;

  /// Hata mesajı (sadece error durumunda dolu)
  final String? errorMessage;

  const InAppInlineStatus({
    required this.state,
    this.webViewInfo,
    this.errorMessage,
  });

  /// Yükleniyor mu?
  bool get isLoading => state == InAppInlineState.loading;

  /// Yüklendi mi?
  bool get isLoaded => state == InAppInlineState.loaded;

  /// Hata var mı?
  bool get isError => state == InAppInlineState.error;

  /// İçerik bulunamadı mı?
  bool get isNotFound => state == InAppInlineState.notFound;

  @override
  String toString() {
    return 'InAppInlineStatus(state: $state, webViewInfo: $webViewInfo, errorMessage: $errorMessage)';
  }
}

/// InAppInline builder callback tipi
///
/// [status] - Mevcut yükleme durumu ve bilgileri
/// [view] - WebView widget'ı (loaded durumunda bunu return et)
typedef InAppInlineBuilder = Widget Function(
    InAppInlineStatus status, Widget view);

/// InAppInline widget - WebView içeriği yüklenene kadar görünmez kalır
class InAppInline extends StatefulWidget {
  final String propertyId;
  final String? screenName;
  final HashMap<String, String>? customParams;

  /// Durum değişikliklerinde çağrılan builder fonksiyonu
  ///
  /// Bu fonksiyon her durum değişikliğinde çağrılır:
  /// - `loading`: Yükleniyor - loading widget döndür
  /// - `loaded`: Yüklendi - view'ı döndür
  /// - `error`: Hata - hata widget'ı veya view döndür
  /// - `notFound`: Bulunamadı - SizedBox.shrink() döndürerek gizle
  ///
  /// ```dart
  /// InAppInline(
  ///   propertyId: "banner",
  ///   builder: (status, view) {
  ///     if (status.isLoading) return CircularProgressIndicator();
  ///     if (status.isNotFound) return SizedBox.shrink();
  ///     if (status.isError) return Text('Hata: ${status.errorMessage}');
  ///     return view; // WebView'ı göster
  ///   },
  /// )
  /// ```
  final InAppInlineBuilder builder;

  /// İçerik yükleme timeout süresi (varsayılan: 10 saniye)
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

  /// Mevcut durum
  InAppInlineStatus get status => _status;

  @override
  void initState() {
    super.initState();
    _startTimeoutTimer();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _startTimeoutTimer() {
    _timeoutTimer = Timer(widget.timeout, () {
      if (mounted && _status.isLoading) {
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
    _channel = MethodChannel('plugins.dengage/inappinline_$viewId');
    _channel?.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
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
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return AndroidView(
          viewType: 'plugins.dengage/inappinline',
          creationParams: _creationParams,
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: _onPlatformViewCreated,
        );
      case TargetPlatform.iOS:
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
    // Platform view oluştur
    final platformView = _buildPlatformView();

    // Yükleme tamamlanana kadar görünmez tut
    final view = Opacity(
      opacity: _status.isLoaded ? 1.0 : 0.0,
      child: platformView,
    );

    // Builder'ı çağır
    return widget.builder(_status, view);
  }
}
