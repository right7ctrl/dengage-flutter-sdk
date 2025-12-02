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
    private var isInitialized = false
    private weak var currentWebView: WKWebView?
    private var visibilityObserver: NSKeyValueObservation?
    private var boundsObserver: NSKeyValueObservation?
    
    // Store Dengage parameters
    private var propertyId: String?
    private var screenName: String?
    private var customParams: Dictionary<String, String>?
    private var dengageInitialized = false
    private let viewId: Int64
    
    // Polling timer for bounds checking (more reliable than KVO on iOS)
    private var boundsCheckTimer: Timer?
    private var lastKnownBounds: CGRect = .zero
    
    func view() -> UIView {
        return _nativeWebView
    }
    
    init(
        frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?,
        messenger: FlutterBinaryMessenger
    ) {
     
        
        // Initialize viewId BEFORE super.init (required for let properties)
        self.viewId = viewId
        
        _nativeWebView = InAppInlineElementView(frame: frame)
        print("\(TAG) InAppInlineElementView created with frame: \(frame)")
        
        methodChannel = FlutterMethodChannel(
            name: "plugins.dengage/inappinline_\(viewId)",
            binaryMessenger: messenger
        )

        
        super.init()
        
        // CRITICAL: Set autoresizing mask so view resizes with parent
        _nativeWebView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        print("\(TAG) autoresizingMask set to flexibleWidth + flexibleHeight")
        
        // Start invisible, will animate to visible when content loads
        _nativeWebView.alpha = 0.0
        _nativeWebView.isHidden = false

        
        // Store Dengage parameters (will be used when view is laid out)
        if let data = args as? [String: Any] {
            self.propertyId = data["propertyId"] as? String
            self.customParams = data["customParams"] as? Dictionary<String, String>
            self.screenName = data["screenName"] as? String
            
           
        } else {
            print("\(TAG) ERROR: args is not [String: Any]!")
        }
        
        // Wait for Flutter to layout the view, then initialize Dengage
        // 0.3s is enough for Flutter's initial layout pass
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            print("\(TAG) Initializing Dengage after layout delay")
            print("\(TAG) Current bounds: \(self._nativeWebView.bounds)")
            self.initializeDengage()
        }
        
        print("\(TAG) ========== InAppInline INIT END ==========")
    }
    
    deinit {
        print("\(TAG) deinit called - cleaning up observers")
        visibilityObserver?.invalidate()
        boundsObserver?.invalidate()
        visibilityObserver = nil
        boundsObserver = nil
        print("\(TAG) deinit completed")
    }
    
    private func logWebViewState() {
        guard let webView = findWKWebView(in: _nativeWebView) else {
            print("\(TAG) logWebViewState - WKWebView not found")
            return
        }
        
      
    }
    
    private func checkIfAlreadyLoaded() {
        guard let webView = findWKWebView(in: _nativeWebView) else {
            print("\(TAG) checkIfAlreadyLoaded - WKWebView not found, will wait for navigation events")
            return
        }
        
        print("\(TAG) checkIfAlreadyLoaded - isLoading: \(webView.isLoading), progress: \(webView.estimatedProgress), URL: \(webView.url?.absoluteString ?? "nil")")
        
        // If already loaded, check content
        if !webView.isLoading && webView.estimatedProgress >= 1.0 {
            print("\(TAG) Page already loaded, checking content...")
            checkContentAndNotify(webView: webView)
        } else {
            print("\(TAG) Page not loaded yet, will wait for didFinish navigation event")
        }
    }
    
    private func checkContentAndNotify(webView: WKWebView, retryCount: Int = 0) {
        let attemptMsg = "checkContentAndNotify attempt #\(retryCount + 1)"
        print("\(TAG) \(attemptMsg)")
        sendDebugLog(attemptMsg)
        
        // Check if view is hidden by SDK (means no content)
        if _nativeWebView.isHidden {
            let msg = "View is HIDDEN by SDK → content not found"
            print("\(TAG) \(msg)")
            sendDebugLog(msg)
            if !isContentLoaded && !isNotFoundNotified {
                notifyContentNotFound()
            }
            return
        }
        
        // HTML content check - is body empty?
        let script = "(function() { return document.body ? document.body.innerHTML.trim().length : 0; })()"
        
        webView.evaluateJavaScript(script) { [weak self] result, error in
            guard let self = self else { return }
            
            let contentLength = (result as? Int) ?? 0
            let lengthMsg = "Body content length: \(contentLength)"
            print("\(TAG) \(lengthMsg)")
            self.sendDebugLog(lengthMsg)
            
            if let error = error {
                print("\(TAG) checkContentAndNotify - JavaScript error: \(error.localizedDescription)")
            }
            
            if contentLength > 0 && !self.isContentLoaded && !self.isNotFoundNotified {
                // Content found!
                let foundMsg = "✅ Content FOUND! Length: \(contentLength)"
                print("\(TAG) \(foundMsg)")
                self.sendDebugLog(foundMsg)
                self.isContentLoaded = true
                
                UIView.animate(withDuration: 0.15) {
                    self._nativeWebView.alpha = 1.0
                }
                print("\(TAG) View made VISIBLE with animation")
                
                // Wait a bit for layout to complete before collecting dimensions
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.collectWebViewInfoAndNotify(webView: webView)
                }
            } else if contentLength == 0 && retryCount < 5 {
                // No content yet, retry (max 5 times)
                let delay = 0.5 + Double(retryCount) * 0.2 // Increasing delay: 0.5s, 0.7s, 0.9s, 1.1s, 1.3s
                let retryMsg = "No content yet, will retry in \(delay)s (attempt \(retryCount + 1)/5)"
                print("\(TAG) \(retryMsg)")
                self.sendDebugLog(retryMsg)
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if !self.isContentLoaded && !self.isNotFoundNotified {
                        self.checkContentAndNotify(webView: webView, retryCount: retryCount + 1)
                    }
                }
            } else if contentLength == 0 && retryCount >= 5 {
                // No content after all retries
                let giveUpMsg = "No content after \(retryCount + 1) attempts, giving up"
                print("\(TAG) \(giveUpMsg)")
                self.sendDebugLog(giveUpMsg)
                if !self.isContentLoaded && !self.isNotFoundNotified {
                    self.notifyContentNotFound()
                }
            }
        }
    }
    
    private func setupBoundsObserver() {
        print("\(TAG) Setting up bounds observer")
        
        // Observe bounds changes - when Flutter lays out the view
        boundsObserver = _nativeWebView.observe(\.bounds, options: [.new]) { [weak self] view, change in
            guard let self = self else { return }
            let newBounds = change.newValue ?? .zero
            


            
            // Initialize Dengage when view has non-zero size
            if newBounds.width > 0 && newBounds.height > 0 && !self.dengageInitialized {
                print("\(TAG) >>> View has size! Initializing Dengage...")
                self.initializeDengage()
            }
        }
        
        print("\(TAG) Bounds observer added")
    }
    
    private func initializeDengage() {
        guard !dengageInitialized else {
            print("\(TAG) initializeDengage - Already initialized, skipping")
            return
        }
        
        guard let propertyId = self.propertyId else {
            print("\(TAG) ERROR: propertyId is nil!")
            return
        }
        
        dengageInitialized = true
        
        
        
        let beforeState = "BEFORE SDK: isHidden=\(_nativeWebView.isHidden), bounds=\(_nativeWebView.bounds), alpha=\(_nativeWebView.alpha)"
        print("\(TAG) \(beforeState)")
        sendDebugLog(beforeState)
        
        Dengage.showInAppInLine(
            propertyID: propertyId,
            inAppInlineElement: _nativeWebView,
            screenName: screenName,
            customParams: customParams
        )
        
        let afterState = "AFTER SDK: isHidden=\(_nativeWebView.isHidden), bounds=\(_nativeWebView.bounds), alpha=\(_nativeWebView.alpha), subviews=\(_nativeWebView.subviews.count)"
        

        
        // THEN set up delegates (to override what SDK sets)
        // Wait for SDK to initialize and potentially load content
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            let state05 = "0.5s AFTER SDK: isHidden=\(self._nativeWebView.isHidden), bounds=\(self._nativeWebView.bounds)"
            print("\(TAG) \(state05)")
            self.sendDebugLog(state05)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            
            self.setupWebViewDelegate()
            self.isInitialized = true
            
            // Log WebView state
            self.logWebViewState()
            
            // If page is already loaded, check content
            self.checkIfAlreadyLoaded()
            
            // Set up visibility observers AFTER initial loading attempt
            // This prevents false "notFound" during initialization
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.setupVisibilityObservers()
            }
        }
        
    }
    
    private func setupVisibilityObservers() {
        
        // Only observe isHidden - SDK explicitly hides view when no content
        visibilityObserver = _nativeWebView.observe(\.isHidden, options: [.new, .old]) { [weak self] view, change in
            guard let self = self else { return }
            let oldValue = change.oldValue ?? false
            let newValue = change.newValue ?? false
            
            
            // Only trigger if view becomes hidden AND we haven't loaded content yet
            if !oldValue && newValue && !self.isContentLoaded && !self.isNotFoundNotified {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    if !self.isContentLoaded && !self.isNotFoundNotified && self._nativeWebView.isHidden {
                        self.notifyContentNotFound()
                    }
                }
            }
        }
        
        // Note: We removed bounds observer as it was too aggressive
        // SDK sets bounds during initialization which triggered false "notFound"
        
    }
    
    private func checkAndNotifyNotFound() {
        
        
        guard !isContentLoaded && !isNotFoundNotified else {
            
            return
        }
        
        if _nativeWebView.isHidden {
            
            notifyContentNotFound()
        } else {
            
        }
    }
    
    private func sendDebugLog(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            
            // Also send to Flutter console via print
            self?.methodChannel.invokeMethod("onDebugLog", arguments: ["message": message])
        }
    }
    
    private func notifyContentNotFound() {
        guard !isNotFoundNotified else {
            return
        }
        isNotFoundNotified = true
        
        let debugInfo = "CONTENT NOT FOUND - isHidden: \(_nativeWebView.isHidden), bounds: \(_nativeWebView.bounds), alpha: \(_nativeWebView.alpha)"
        
        sendDebugLog(debugInfo)
        
        methodChannel.invokeMethod("onContentNotFound", arguments: nil)
        print("\(TAG) onContentNotFound sent to Flutter")
    }
    
    private func setupWebViewDelegate() {
        print("\(TAG) Setting up WebView delegate")
        
        if let webView = findWKWebView(in: _nativeWebView) {
            webView.navigationDelegate = self
            currentWebView = webView
            
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
        
        
        guard !isContentLoaded && !isNotFoundNotified else {
            
            return
        }
        isContentLoaded = true
        
        UIView.animate(withDuration: 0.15) {
            self._nativeWebView.alpha = 1.0
        }
        
        collectWebViewInfoAndNotify(webView: webView)
    }
    
    private func collectWebViewInfoAndNotify(webView: WKWebView) {
        print("\(TAG) collectWebViewInfoAndNotify - Starting")
        print("\(TAG) WebView URL: \(webView.url?.absoluteString ?? "nil")")
        print("\(TAG) WebView Title: \(webView.title ?? "nil")")
        print("\(TAG) WebView frame: \(webView.frame)")
        print("\(TAG) Native view frame: \(_nativeWebView.frame)")
        
        let nativeFrame = _nativeWebView.frame
        
        // If native frame is valid, use it
        if nativeFrame.width > 0 && nativeFrame.height > 0 {
            let contentHeight = Double(nativeFrame.height)
            let contentWidth = Double(nativeFrame.width)
            
            let webViewInfo: [String: Any?] = [
                "url": webView.url?.absoluteString,
                "title": webView.title,
                "contentHeight": contentHeight,
                "contentWidth": contentWidth,
                "canGoBack": webView.canGoBack,
                "canGoForward": webView.canGoForward
            ]
            
            
            self.methodChannel.invokeMethod("onContentLoaded", arguments: webViewInfo)
        } else {
            // Fallback to JavaScript if native frame is 0
            print("\(TAG) ⚠️ Native frame is 0x0, falling back to JavaScript")
            
            let script = """
                (function() {
                    var body = document.body;
                    var html = document.documentElement;
                    return {
                        height: Math.max(body.scrollHeight || 0, body.offsetHeight || 0, html.scrollHeight || 0, html.offsetHeight || 0, 150),
                        width: Math.max(body.scrollWidth || 0, body.offsetWidth || 0, html.scrollWidth || 0, html.offsetWidth || 0, 300)
                    };
                })();
            """
            
            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self = self else { return }
                
                
                var contentHeight: Double = 150.0 // Default fallback
                var contentWidth: Double = 300.0  // Default fallback
                
                if let dimensions = result as? [String: Any] {
                    contentHeight = dimensions["height"] as? Double ?? 150.0
                    contentWidth = dimensions["width"] as? Double ?? 300.0
                }
                
                
                let webViewInfo: [String: Any?] = [
                    "url": webView.url?.absoluteString,
                    "title": webView.title,
                    "contentHeight": contentHeight,
                    "contentWidth": contentWidth,
                    "canGoBack": webView.canGoBack,
                    "canGoForward": webView.canGoForward
                ]
                
                
                self.methodChannel.invokeMethod("onContentLoaded", arguments: webViewInfo)
            }
        }
    }
    
    private func notifyContentError(error: Error?) {
        methodChannel.invokeMethod("onContentError", arguments: [
            "description": error?.localizedDescription ?? "Unknown error"
        ])
    }
}

// MARK: - WKNavigationDelegate
extension InAppinline: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
       
        // HTML içeriğini kontrol et
        if !isContentLoaded && !isNotFoundNotified {
            checkContentAndNotify(webView: webView)
        } else {
            print("\(TAG) >>> didFinish - SKIPPED (already loaded or notFound)")
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        
        notifyContentError(error: error)
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        
        notifyContentError(error: error)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        decisionHandler(.allow)
    }
}
