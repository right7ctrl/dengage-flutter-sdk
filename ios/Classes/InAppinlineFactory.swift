import Foundation
import Flutter
import UIKit

private let TAG = "[InAppInlineFactory]"

class InAppinlineFactory: NSObject, FlutterPlatformViewFactory {
    private var messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        print("\(TAG) ========== FACTORY INITIALIZED ==========")
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        print("\(TAG) ========== CREATE CALLED - ID: \(viewId) ==========")
        print("\(TAG) Frame: \(frame)")
        print("\(TAG) Arguments: \(String(describing: args))")
        
        let view = InAppinline(
            frame: frame,
            viewIdentifier: viewId,
            arguments: args,
            messenger: messenger
        )
        
        print("\(TAG) ========== CREATE COMPLETED - ID: \(viewId) ==========")
        return view
    }
    
    public func createArgsCodec() -> any FlutterMessageCodec & NSObjectProtocol {
       return FlutterStandardMessageCodec.sharedInstance()
    }
}
