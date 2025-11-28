import Foundation
import Flutter
import UIKit
import WebKit
import Dengage

private let TAG = "[den/InAppInline]"

class InAppinline: NSObject, FlutterPlatformView {
    private var _nativeWebView: InAppInlineElementView
    private var methodChannel: FlutterMethodChannel
    private var isContentLoaded = false
    private var isNotFoundNotified = false
    private weak var currentWebView: WKWebView?
    private var visibilityObserver: NSKeyValueObservation?
    private var boundsObserver: NSKeyValueObservation?
    
    func view() -> UIView {
        return _nativeWebView
    }
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        messenger: FlutterBinaryMessenger
    ) {
        print("\(TAG) ========== InAppInline INIT START ==========")
        print("\(TAG) viewId: \(viewId)")
        print("\(TAG) arguments: \(String(describing: args))")
        
        _nativeWebView = InAppInlineElementView()
        print("\(TAG) InAppInlineElementView created")
        
        methodChannel = FlutterMethodChannel(
            name: "plugins.dengage/inappinline_\(viewId)",
            binaryMessenger: messenger
        )
        print("\(TAG) MethodChannel created: plugins.dengage/inappinline_\(viewId)")
            
        super.init()
        
        _nativeWebView.alpha = 0.0
        print("\(TAG) Initial alpha: 0.0")
        
        setupWebViewDelegate()
        setupVisibilityObservers()
        
        if let data = args as? [String: Any] {
            let propertyId = data["propertyId"] as? String
            let customParams = data["customParams"] as? Dictionary<String, String>
            let screenName = data["screenName"] as? String
            
            print("\(TAG) Calling Dengage.showInAppInLine with:")
            print("\(TAG)   - propertyId: \(propertyId ?? "nil")")
            print("\(TAG)   - screenName: \(screenName ?? "nil")")
            print("\(TAG)   - customParams: \(String(describing: customParams))")
            
            if let propertyId = propertyId {
                Dengage.showInAppInLine(
                    propertyID: propertyId,
                    inAppInlineElement: _nativeWebView,
                    screenName: screenName,
                    customParams: customParams
                )
                print("\(TAG) Dengage.showInAppInLine called")
            } else {
                print("\(TAG) ERROR: propertyId is nil!")
            }
        } else {
            print("\(TAG) ERROR: args is not [String: Any]!")
        }
        
        print("\(TAG) ========== InAppInline INIT END ==========")
    }
    
    deinit {
        print("\(TAG) deinit called")
        visibilityObserver?.invalidate()
        boundsObserver?.invalidate()
    }
    
    private func setupVisibilityObservers() {
        print("\(TAG) Setting up visibility observers")
        
        visibilityObserver = _nativeWebView.observe(\.isHidden, options: [.new, .old]) { [weak self] view, change in
            guard let self = self else { return }
            print("\(TAG) >>> isHidden changed - old: \(change.oldValue ?? false), new: \(change.newValue ?? false)")
            if let isHidden = change.newValue, isHidden {
                self.checkAndNotifyNotFound()
            }
        }
        
        boundsObserver = _nativeWebView.observe(\.bounds, options: [.new, .old]) { [weak self] view, change in
            guard let self = self else { return }
            let oldBounds = change.oldValue ?? .zero
            let newBounds = change.newValue ?? .zero
            print("\(TAG) >>> bounds changed - old: \(oldBounds), new: \(newBounds)")
            print("\(TAG) >>> bounds - isContentLoaded: \(self.isContentLoaded), isNotFoundNotified: \(self.isNotFoundNotified)")
            
            if newBounds.height == 0 && newBounds.width == 0 {
                print("\(TAG) >>> bounds are zero, scheduling notFound check in 0.5s")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.checkAndNotifyNotFound()
                }
            }
        }
        
        print("\(TAG) Visibility observers added")
    }
    
    private func checkAndNotifyNotFound() {
        print("\(TAG) checkAndNotifyNotFound called")
        print("\(TAG)   - isContentLoaded: \(isContentLoaded)")
        print("\(TAG)   - isNotFoundNotified: \(isNotFoundNotified)")
        print("\(TAG)   - isHidden: \(_nativeWebView.isHidden)")
        print("\(TAG)   - bounds: \(_nativeWebView.bounds)")
        
        guard !isContentLoaded && !isNotFoundNotified else {
            print("\(TAG) checkAndNotifyNotFound - SKIPPED (already loaded or notified)")
            return
        }
        
        if _nativeWebView.isHidden || (_nativeWebView.bounds.height == 0 && _nativeWebView.bounds.width == 0) {
            print("\(TAG) checkAndNotifyNotFound - View appears hidden, calling notifyContentNotFound")
            notifyContentNotFound()
        } else {
            print("\(TAG) checkAndNotifyNotFound - View is visible, NOT calling notifyContentNotFound")
        }
    }
    
    private func notifyContentNotFound() {
        guard !isNotFoundNotified else {
            print("\(TAG) notifyContentNotFound - Already notified, skipping")
            return
        }
        isNotFoundNotified = true
        
        print("\(TAG) ========== CONTENT NOT FOUND ==========")
        print("\(TAG) View isHidden: \(_nativeWebView.isHidden)")
        print("\(TAG) View bounds: \(_nativeWebView.bounds)")
        print("\(TAG) View alpha: \(_nativeWebView.alpha)")
        
        methodChannel.invokeMethod("onContentNotFound", arguments: nil)
        print("\(TAG) Flutter'a onContentNotFound gönderildi")
    }
    
    private func setupWebViewDelegate() {
        print("\(TAG) Setting up WebView delegate")
        
        if let webView = findWKWebView(in: _nativeWebView) {
            webView.navigationDelegate = self
            currentWebView = webView
            print("\(TAG) WKWebView found and delegate set")
        } else {
            print("\(TAG) WKWebView NOT found, retrying in 0.1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.retrySetupWebViewDelegate()
            }
        }
    }
    
    private func retrySetupWebViewDelegate() {
        print("\(TAG) retrySetupWebViewDelegate called")
        if let webView = findWKWebView(in: _nativeWebView) {
            webView.navigationDelegate = self
            currentWebView = webView
            print("\(TAG) WKWebView found on retry and delegate set")
        } else {
            print("\(TAG) WKWebView still NOT found on retry")
        }
    }
    
    private func findWKWebView(in view: UIView) -> WKWebView? {
        if let webView = view as? WKWebView {
            return webView
        }
        for subview in view.subviews {
            if let webView = findWKWebView(in: subview) {
                return webView
            }
        }
        return nil
    }
    
    private func notifyContentLoaded(webView: WKWebView) {
        print("\(TAG) notifyContentLoaded called")
        print("\(TAG)   - isContentLoaded: \(isContentLoaded)")
        print("\(TAG)   - isNotFoundNotified: \(isNotFoundNotified)")
        
        guard !isContentLoaded && !isNotFoundNotified else {
            print("\(TAG) notifyContentLoaded - SKIPPED (already loaded or notFound)")
            return
        }
        isContentLoaded = true
        print("\(TAG) Setting isContentLoaded = true")
        
        UIView.animate(withDuration: 0.15) {
            self._nativeWebView.alpha = 1.0
        }
        print("\(TAG) View made visible with animation")
        
        collectWebViewInfoAndNotify(webView: webView)
    }
    
    private func collectWebViewInfoAndNotify(webView: WKWebView) {
        print("\(TAG) collectWebViewInfoAndNotify - Starting")
        print("\(TAG) WebView URL: \(webView.url?.absoluteString ?? "nil")")
        print("\(TAG) WebView Title: \(webView.title ?? "nil")")
        
        let script = """
            (function() {
                return {
                    height: document.body.scrollHeight,
                    width: document.body.scrollWidth
                };
            })();
        """
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            
            print("\(TAG) JavaScript result: \(String(describing: result))")
            if let error = error {
                print("\(TAG) JavaScript error: \(error.localizedDescription)")
            }
            
            var contentHeight: Double? = nil
            var contentWidth: Double? = nil
            
            if let dimensions = result as? [String: Any] {
                contentHeight = dimensions["height"] as? Double
                contentWidth = dimensions["width"] as? Double
            }
            
            let webViewInfo: [String: Any?] = [
                "url": webView.url?.absoluteString,
                "title": webView.title,
                "contentHeight": contentHeight,
                "contentWidth": contentWidth,
                "canGoBack": webView.canGoBack,
                "canGoForward": webView.canGoForward
            ]
            
            print("\(TAG) ========== CONTENT LOADED ==========")
            print("\(TAG) WebView info: \(webViewInfo)")
            
            self.methodChannel.invokeMethod("onContentLoaded", arguments: webViewInfo)
            print("\(TAG) Flutter'a onContentLoaded gönderildi")
        }
    }
    
    private func notifyContentError(error: Error?) {
        print("\(TAG) notifyContentError - error: \(error?.localizedDescription ?? "nil")")
        methodChannel.invokeMethod("onContentError", arguments: [
            "description": error?.localizedDescription ?? "Unknown error"
        ])
        print("\(TAG) Flutter'a onContentError gönderildi")
    }
}

// MARK: - WKNavigationDelegate
extension InAppinline: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        print("\(TAG) >>> didStartProvisionalNavigation")
        print("\(TAG) >>> URL: \(webView.url?.absoluteString ?? "nil")")
            }
            
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        print("\(TAG) >>> didCommit navigation")
        print("\(TAG) >>> URL: \(webView.url?.absoluteString ?? "nil")")
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        print("\(TAG) >>> didFinish navigation")
        print("\(TAG) >>> URL: \(webView.url?.absoluteString ?? "nil")")
        print("\(TAG) >>> isContentLoaded: \(isContentLoaded), isNotFoundNotified: \(isNotFoundNotified)")
        notifyContentLoaded(webView: webView)
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("\(TAG) >>> didFail navigation")
        print("\(TAG) >>> Error: \(error.localizedDescription)")
        notifyContentError(error: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("\(TAG) >>> didFailProvisionalNavigation")
        print("\(TAG) >>> Error: \(error.localizedDescription)")
        notifyContentError(error: error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        print("\(TAG) >>> decidePolicyFor navigationAction")
        print("\(TAG) >>> Request URL: \(navigationAction.request.url?.absoluteString ?? "nil")")
        decisionHandler(.allow)
    }
}
