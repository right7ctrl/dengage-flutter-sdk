package com.example.dengage_flutter

import android.app.Activity
import android.content.Context
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory


class InAppInlineFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger
) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    
    init {
        Log.e("InAppInlineFactory", "========== FACTORY CREATED ==========")
    }
    
    override fun create(context: Context, id: Int, args: Any?): PlatformView {
        Log.e("InAppInlineFactory", "========== CREATE CALLED - ID: $id ==========")
        Log.e("InAppInlineFactory", "Args: $args")
        val creationParams = args as HashMap<String, Any>
        val inAppInline = InAppInline(context, creationParams, activity, messenger, id)
        Log.e("InAppInlineFactory", "========== InAppInline CREATED ==========")
        return inAppInline
    }
}
