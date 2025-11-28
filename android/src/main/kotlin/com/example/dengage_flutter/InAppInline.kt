package com.example.dengage_flutter

import android.app.Activity
import android.content.Context
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.ViewTreeObserver
import android.webkit.ConsoleMessage
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import com.dengage.sdk.Dengage
import com.dengage.sdk.ui.inappmessage.InAppInlineElement
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

private const val TAG = "den/InAppInline"

class InAppInline internal constructor(
    context: Context,
    creationParams: HashMap<String, Any>,
    activity: Activity,
    messenger: BinaryMessenger,
    viewId: Int
) :
    PlatformView {
    private lateinit var inAppInlineElement: InAppInlineElement
    private var methodChannel: MethodChannel
    private var isContentLoaded = false
    private var isNotFoundNotified = false
    private var isInitialized = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private var visibilityListener: ViewTreeObserver.OnGlobalLayoutListener? = null
    private var notFoundRunnable: Runnable? = null

    override fun getView(): View {
        return inAppInlineElement
    }

    init {
        Log.d(TAG, "========== InAppInline INIT START ==========")
        Log.d(TAG, "viewId: $viewId")
        Log.d(TAG, "creationParams: $creationParams")
        
        methodChannel = MethodChannel(messenger, "plugins.dengage/inappinline_$viewId")
        Log.d(TAG, "MethodChannel created: plugins.dengage/inappinline_$viewId")

        inAppInlineElement = InAppInlineElement(context)
        Log.d(TAG, "InAppInlineElement created")
        
        inAppInlineElement.visibility = View.INVISIBLE
        inAppInlineElement.alpha = 0f
        Log.d(TAG, "Initial visibility: INVISIBLE, alpha: 0")

        val propertyId = creationParams["propertyId"] as String
        val customParams = creationParams["customParams"] as HashMap<String, String>?
        val screenName = creationParams["screenName"] as String?
        
        Log.d(TAG, "Calling Dengage.showInlineInApp with:")
        Log.d(TAG, "  - propertyId: $propertyId")
        Log.d(TAG, "  - screenName: $screenName")
        Log.d(TAG, "  - customParams: $customParams")
        
        Dengage.showInlineInApp(
            activity = activity,
            propertyId = propertyId,
            inAppInlineElement = inAppInlineElement,
            customParams = customParams,
            screenName = screenName
        )
        Log.d(TAG, "Dengage.showInlineInApp called")
        
        mainHandler.postDelayed({
            setupWebViewClient()
            setupWebChromeClient()
            setupVisibilityListener()
            isInitialized = true
            Log.d(TAG, "Initialization completed (delayed)")
            
            logWebViewState()
        }, 100)
        
        Log.d(TAG, "========== InAppInline INIT END ==========")
    }

    private fun logWebViewState() {
        Log.d(TAG, "========== WebView State ==========")
        Log.d(TAG, "URL: ${inAppInlineElement.url}")
        Log.d(TAG, "Original URL: ${inAppInlineElement.originalUrl}")
        Log.d(TAG, "Title: ${inAppInlineElement.title}")
        Log.d(TAG, "Progress: ${inAppInlineElement.progress}%")
        Log.d(TAG, "Visibility: ${inAppInlineElement.visibility}")
        Log.d(TAG, "Width: ${inAppInlineElement.width}, Height: ${inAppInlineElement.height}")
        Log.d(TAG, "Settings JS Enabled: ${inAppInlineElement.settings.javaScriptEnabled}")
        Log.d(TAG, "===================================")
    }

    private fun setupWebChromeClient() {
        Log.d(TAG, "Setting up WebChromeClient")
        
        inAppInlineElement.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView?, newProgress: Int) {
                super.onProgressChanged(view, newProgress)
                Log.d(TAG, ">>> onProgressChanged - Progress: $newProgress%")
                
                if (newProgress == 100) {
                    Log.d(TAG, ">>> onProgressChanged - Loading complete!")
                }
            }
            
            override fun onConsoleMessage(consoleMessage: ConsoleMessage?): Boolean {
                Log.d(TAG, ">>> Console [${consoleMessage?.messageLevel()}]: ${consoleMessage?.message()}")
                Log.d(TAG, ">>> Console - Source: ${consoleMessage?.sourceId()}:${consoleMessage?.lineNumber()}")
                return super.onConsoleMessage(consoleMessage)
            }
            
            override fun onReceivedTitle(view: WebView?, title: String?) {
                super.onReceivedTitle(view, title)
                Log.d(TAG, ">>> onReceivedTitle - Title: $title")
            }
        }
        Log.d(TAG, "WebChromeClient set")
    }

    private fun setupWebViewClient() {
        Log.d(TAG, "Setting up WebViewClient")
        
        val existingClient = inAppInlineElement.webViewClient
        Log.d(TAG, "Existing WebViewClient: $existingClient")
        
        inAppInlineElement.webViewClient = object : WebViewClient() {
            override fun onPageStarted(view: WebView?, url: String?, favicon: Bitmap?) {
                existingClient?.onPageStarted(view, url, favicon)
                Log.d(TAG, ">>> onPageStarted - URL: $url")
                Log.d(TAG, ">>> onPageStarted - isContentLoaded: $isContentLoaded, isNotFoundNotified: $isNotFoundNotified")
                
                cancelNotFoundCheck()
            }

            override fun onPageFinished(view: WebView?, url: String?) {
                existingClient?.onPageFinished(view, url)
                Log.d(TAG, ">>> onPageFinished - URL: $url")
                Log.d(TAG, ">>> onPageFinished - isContentLoaded: $isContentLoaded, isNotFoundNotified: $isNotFoundNotified")
                Log.d(TAG, ">>> onPageFinished - view: $view")
                
                if (!isContentLoaded && !isNotFoundNotified && view != null) {
                    val currentUrl = view.url
                    Log.d(TAG, ">>> onPageFinished - currentUrl: $currentUrl")
                    
                    view.evaluateJavascript(
                        "(function() { return document.body ? document.body.innerHTML.trim().length : 0; })()"
                    ) { result ->
                        val contentLength = result?.replace("\"", "")?.toIntOrNull() ?: 0
                        Log.d(TAG, ">>> onPageFinished - Body content length: $contentLength")
                        
                        if (contentLength > 0) {
                            Log.d(TAG, ">>> onPageFinished - Content found! Setting isContentLoaded = true")
                            
                            if (!isContentLoaded && !isNotFoundNotified) {
                                isContentLoaded = true
                                cancelNotFoundCheck()
                                
                                inAppInlineElement.visibility = View.VISIBLE
                                inAppInlineElement.animate()
                                    .alpha(1f)
                                    .setDuration(150)
                                    .start()
                                Log.d(TAG, ">>> onPageFinished - View made VISIBLE with animation")
                                
                                collectWebViewInfoAndNotify(view)
                            }
                        } else {
                            Log.d(TAG, ">>> onPageFinished - No content, scheduling notFound check")
                            scheduleNotFoundCheck(1000)
                        }
                    }
                    return
                } else {
                    Log.d(TAG, ">>> onPageFinished - SKIPPED: isContentLoaded=$isContentLoaded, isNotFoundNotified=$isNotFoundNotified, view=$view")
                }
            }

            override fun onReceivedError(
                view: WebView?,
                errorCode: Int,
                description: String?,
                failingUrl: String?
            ) {
                existingClient?.onReceivedError(view, errorCode, description, failingUrl)
                Log.e(TAG, ">>> onReceivedError - errorCode: $errorCode, description: $description, failingUrl: $failingUrl")
                
                try {
                    methodChannel.invokeMethod("onContentError", mapOf(
                        "errorCode" to errorCode,
                        "description" to description
                    ))
                    Log.d(TAG, ">>> onReceivedError - Flutter'a onContentError gönderildi")
                } catch (e: Exception) {
                    Log.e(TAG, ">>> onReceivedError - Flutter invoke error: ${e.message}")
                }
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: WebResourceError?
            ) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    Log.e(TAG, ">>> onReceivedError (API 23+)")
                    Log.e(TAG, ">>>   URL: ${request?.url}")
                    Log.e(TAG, ">>>   isForMainFrame: ${request?.isForMainFrame}")
                    Log.e(TAG, ">>>   errorCode: ${error?.errorCode}")
                    Log.e(TAG, ">>>   description: ${error?.description}")
                }
                super.onReceivedError(view, request, error)
            }
            
            override fun onReceivedHttpError(
                view: WebView?,
                request: WebResourceRequest?,
                errorResponse: WebResourceResponse?
            ) {
                Log.e(TAG, ">>> onReceivedHttpError")
                Log.e(TAG, ">>>   URL: ${request?.url}")
                Log.e(TAG, ">>>   Status Code: ${errorResponse?.statusCode}")
                Log.e(TAG, ">>>   Reason: ${errorResponse?.reasonPhrase}")
                Log.e(TAG, ">>>   Headers: ${errorResponse?.responseHeaders}")
                super.onReceivedHttpError(view, request, errorResponse)
            }

            override fun onReceivedSslError(
                view: WebView?,
                handler: SslErrorHandler?,
                error: SslError?
            ) {
                Log.e(TAG, ">>> onReceivedSslError - error: $error")
                super.onReceivedSslError(view, handler, error)
            }
            
            override fun shouldOverrideUrlLoading(view: WebView?, url: String?): Boolean {
                Log.d(TAG, ">>> shouldOverrideUrlLoading - URL: $url")
                return existingClient?.shouldOverrideUrlLoading(view, url) ?: super.shouldOverrideUrlLoading(view, url)
            }

            override fun shouldOverrideUrlLoading(
                view: WebView?,
                request: WebResourceRequest?
            ): Boolean {
                Log.d(TAG, ">>> shouldOverrideUrlLoading (API 24+)")
                Log.d(TAG, ">>>   URL: ${request?.url}")
                Log.d(TAG, ">>>   Method: ${request?.method}")
                Log.d(TAG, ">>>   Headers: ${request?.requestHeaders}")
                return super.shouldOverrideUrlLoading(view, request)
            }
            
            override fun onLoadResource(view: WebView?, url: String?) {
                existingClient?.onLoadResource(view, url)
                Log.d(TAG, ">>> onLoadResource - URL: $url")
            }

            override fun shouldInterceptRequest(
                view: WebView?,
                request: WebResourceRequest?
            ): WebResourceResponse? {
                Log.d(TAG, ">>> shouldInterceptRequest")
                Log.d(TAG, ">>>   URL: ${request?.url}")
                Log.d(TAG, ">>>   Method: ${request?.method}")
                Log.d(TAG, ">>>   Headers: ${request?.requestHeaders}")
                Log.d(TAG, ">>>   isForMainFrame: ${request?.isForMainFrame}")
                return super.shouldInterceptRequest(view, request)
            }

            override fun shouldInterceptRequest(view: WebView?, url: String?): WebResourceResponse? {
                Log.d(TAG, ">>> shouldInterceptRequest (legacy) - URL: $url")
                return super.shouldInterceptRequest(view, url)
            }
        }
        Log.d(TAG, "WebViewClient set (wrapped existing)")
    }

    private fun setupVisibilityListener() {
        Log.d(TAG, "Setting up visibility listener")
        var layoutChangeCount = 0
        
        visibilityListener = ViewTreeObserver.OnGlobalLayoutListener {
            if (!isInitialized) return@OnGlobalLayoutListener
            
            layoutChangeCount++
            val visibility = inAppInlineElement.visibility
            val visibilityStr = when(visibility) {
                View.VISIBLE -> "VISIBLE"
                View.INVISIBLE -> "INVISIBLE"
                View.GONE -> "GONE"
                else -> "UNKNOWN($visibility)"
            }
            val width = inAppInlineElement.width
            val height = inAppInlineElement.height
            
            if (layoutChangeCount <= 5 || layoutChangeCount % 10 == 0) {
                Log.d(TAG, ">>> onGlobalLayout #$layoutChangeCount - visibility: $visibilityStr, width: $width, height: $height")
                Log.d(TAG, ">>> onGlobalLayout - isContentLoaded: $isContentLoaded, isNotFoundNotified: $isNotFoundNotified")
            }
            if (isContentLoaded || isNotFoundNotified) return@OnGlobalLayoutListener
            
            if (visibility == View.GONE) {
                Log.d(TAG, ">>> onGlobalLayout - View is GONE, scheduling notFound check")
                scheduleNotFoundCheck(500)
            }
        }
        inAppInlineElement.viewTreeObserver.addOnGlobalLayoutListener(visibilityListener)
        Log.d(TAG, "Visibility listener added")
    }

    private fun scheduleNotFoundCheck(delayMs: Long) {

        cancelNotFoundCheck()
        
        Log.d(TAG, "Scheduling notFound check in ${delayMs}ms")
        notFoundRunnable = Runnable {
            if (!isContentLoaded && !isNotFoundNotified) {
                val visibility = inAppInlineElement.visibility
                val width = inAppInlineElement.width
                val height = inAppInlineElement.height
                
                Log.d(TAG, ">>> notFound check - visibility: $visibility, width: $width, height: $height")
                

                if (visibility == View.GONE) {
                    notifyContentNotFound()
                }
            }
        }
        mainHandler.postDelayed(notFoundRunnable!!, delayMs)
    }

    private fun cancelNotFoundCheck() {
        notFoundRunnable?.let {
            mainHandler.removeCallbacks(it)
            Log.d(TAG, "NotFound check cancelled")
        }
        notFoundRunnable = null
    }

    private fun notifyContentNotFound() {
        if (isNotFoundNotified) {
            Log.d(TAG, "notifyContentNotFound - Already notified, skipping")
            return
        }
        isNotFoundNotified = true
        
        Log.d(TAG, "========== CONTENT NOT FOUND ==========")
        Log.d(TAG, "View visibility: ${inAppInlineElement.visibility}")
        Log.d(TAG, "View width: ${inAppInlineElement.width}, height: ${inAppInlineElement.height}")
        Log.d(TAG, "WebView URL: ${inAppInlineElement.url}")
        Log.d(TAG, "WebView Original URL: ${inAppInlineElement.originalUrl}")
        
        try {
            methodChannel.invokeMethod("onContentNotFound", null)
            Log.d(TAG, "Flutter'a onContentNotFound gönderildi")
        } catch (e: Exception) {
            Log.e(TAG, "Error invoking onContentNotFound: ${e.message}")
        }
    }

    private fun collectWebViewInfoAndNotify(webView: WebView) {
        Log.d(TAG, "collectWebViewInfoAndNotify - Starting")
        Log.d(TAG, "WebView URL: ${webView.url}")
        Log.d(TAG, "WebView Title: ${webView.title}")
        
        webView.evaluateJavascript(
            "(function() { return document.body.scrollHeight; })();"
        ) { contentHeightStr ->
            Log.d(TAG, "JavaScript scrollHeight result: $contentHeightStr")
            val contentHeight = contentHeightStr?.replace("\"", "")?.toDoubleOrNull()
            
            webView.evaluateJavascript(
                "(function() { return document.body.scrollWidth; })();"
            ) { contentWidthStr ->
                Log.d(TAG, "JavaScript scrollWidth result: $contentWidthStr")
                val contentWidth = contentWidthStr?.replace("\"", "")?.toDoubleOrNull()
                
                mainHandler.post {
                    try {
                        val webViewInfo = mapOf(
                            "url" to webView.url,
                            "title" to webView.title,
                            "contentHeight" to contentHeight,
                            "contentWidth" to contentWidth,
                            "canGoBack" to webView.canGoBack(),
                            "canGoForward" to webView.canGoForward()
                        )
                        
                        Log.d(TAG, "========== CONTENT LOADED ==========")
                        Log.d(TAG, "WebView info: $webViewInfo")
                        methodChannel.invokeMethod("onContentLoaded", webViewInfo)
                        Log.d(TAG, "Flutter'a onContentLoaded gönderildi")
                    } catch (e: Exception) {
                        Log.e(TAG, "Error invoking onContentLoaded: ${e.message}")
                    }
                }
            }
        }
    }

    override fun dispose() {
        Log.d(TAG, "dispose() called")
        cancelNotFoundCheck()
        visibilityListener?.let {
            inAppInlineElement.viewTreeObserver.removeOnGlobalLayoutListener(it)
        }
        inAppInlineElement.destroy()
        Log.d(TAG, "InAppInlineElement destroyed")
    }
}
