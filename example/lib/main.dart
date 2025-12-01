import 'dart:async';
import 'dart:collection';

import 'package:dengage_flutter/dengage_flutter.dart';
import 'package:dengage_flutter/InAppInline.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  DengageFlutter.setLogStatus(true);

  runApp(
    MyApp(),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  //MyHomePage({Key key}) : super(key: key);

  @override
  _MyHomePageState createState() => new _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String contactKey = '';
  String lastPush = '';
  var contactKeyController = TextEditingController();
  var lastPushController = TextEditingController();
  HashMap<String, String> hashMap = new HashMap();

  static const EventChannel eventChannel = EventChannel("com.dengage.flutter/onNotificationClicked");
  static const EventChannel eventChannel2 = EventChannel("com.dengage.flutter/inAppLinkRetrieval");

  void _onEvent(dynamic event) {
    print("in on Event object is: $event");
    print(event);
    lastPushController.text = event.toString();
  }

  void _onError(dynamic error) {
    print("in on Error Object is: ");
    print(error);
  }

  @override
  void initState() {
    DengageFlutter.getContactKey().then((value) {
      print("dengageContactKey: $value");
      //contactKeyChanged(value);
    });
    DengageFlutter.setNavigation();

    //DengageFlutter.startGeofence();
    // print("setting screen name.");
    // DengageFlutter.setNavigationWithName('MainScreen');

    DengageFlutter.handleNotificationActionBlock().then((value) {
      print("dengageContactKey: $value");
      //contactKeyChanged(value);
    });

    DengageFlutter.pageView({
      "page_type": "MerchantStatusRoute",
      "page_url": "MerchantStatusRoute",
      "page_title": "MerchantStatusRoute"
    });
    eventChannel2.receiveBroadcastStream().listen(_onEvent, onError: _onError);
    hashMap["priya"] = "priya";
    super.initState();
  }

  void showAlert(BuildContext context,String value) {
    showDialog(
        context: context,
        builder: (context) => AlertDialog(
          content: Text("hi"),
        ));
  }

  contactKeyChanged(String value) {
    if (value.isNotEmpty) {
      print("$value is not empty.");
      contactKeyController.value = TextEditingValue(
        text: value,
        selection: TextSelection.fromPosition(
          TextPosition(offset: value.length),
        ),
      );
      setState(() {
        contactKey = value;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal,
      appBar: AppBar(
        backgroundColor: Colors.teal[900],
        title: Text('Flutter Sample App'),
      ),
      body: Container(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Enter Your Contact Key'),
            TextFormField(
              controller: contactKeyController,
              decoration: const InputDecoration(
                icon: const Icon(
                  Icons.input,
                  color: Colors.black54,
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.black54,
                  ),
                ),
              ),
              cursorColor: Colors.black54,
              keyboardType: TextInputType.text,
              maxLines: 1,
              onChanged: contactKeyChanged,
            ),
            Container(
              padding: EdgeInsets.only(top: 10.0),
              child: InAppInline(
                propertyId: "home_banner",
                screenName: "MerchantStatusRoute",
                timeout: Duration(seconds: 15),
                builder: (status, inlineContent) {
                  print('status: $status');

                  // Loaded
                  if (status.isLoaded) {
                    print('InAppInline loaded!');
                    print('URL: ${status.webViewInfo?.url}');
                    print('Title: ${status.webViewInfo?.title}');
                    print(
                        'Content Height: ${status.webViewInfo?.contentHeight}');
                  }

                  // Content not found or error - hide completely
                  if (status.isNotFound) {
                    print('InAppInline content not found!');
                    return SizedBox.shrink();
                  }
                  if (status.isError) {
                    print('InAppInline error: ${status.errorMessage}');
                    return SizedBox.shrink();
                  }
                  return Offstage(
                    offstage:
                        status.isNotFound || status.isError || status.isLoading,
                    child: SizedBox(height: 200, child: inlineContent),
                  );
                  // Loading or Loaded - show with fixed height
                  return Stack(
                    children: [
                      SizedBox(
                        height: 200,
                        child: inlineContent,
                      ),
                      if (status.isLoading)
                        SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Container(
              padding: EdgeInsets.only(top: 10.0),
              child: InAppInline(
                propertyId: "404",
                screenName: "MerchantStatusRoute",
                timeout: Duration(seconds: 15),
                builder: (status, inlineContent) {
                  print('status: $status');
                  
                  // Loaded
                  if (status.isLoaded) {
                    print('InAppInline loaded!');
                    print('URL: ${status.webViewInfo?.url}');
                    print('Title: ${status.webViewInfo?.title}');
                    print(
                        'Content Height: ${status.webViewInfo?.contentHeight}');
                  }

                  // Content not found or error - hide completely
                  if (status.isNotFound) {
                    print('InAppInline content not found!');
                    return SizedBox.shrink();
                  }
                  if (status.isError) {
                    print('InAppInline error: ${status.errorMessage}');
                    return SizedBox.shrink();
                  }

                  // Loading or Loaded - show with fixed height
                  return Stack(
                    children: [
                      SizedBox(
                        height: 200,
                        child: inlineContent,
                      ),
                      if (status.isLoading)
                        SizedBox(
                          height: 200,
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),


            Container(
              padding: EdgeInsets.only(top: 10.0),
              child: ElevatedButton(
                onPressed: () async {
                  DengageFlutter.stopGeofence();
                },
                child: Text('set Tags'),
              ),
            ),
            Container(
              padding: EdgeInsets.only(top: 10.0),
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => SecondRoute()));
                },
                child: Text('Navigate to "SecondScreen"'),
              ),
            ),
            Text('Last Push Received.'),
            TextFormField(
              controller: lastPushController,
              decoration: const InputDecoration(
                icon: const Icon(
                  Icons.input,
                  color: Colors.black54,
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(
                    color: Colors.black54,
                  ),
                ),
              ),
              cursorColor: Colors.black54,
              keyboardType: TextInputType.text,
              onChanged: contactKeyChanged,
            ),
          ],
        ),
      ),
    );
  }
}
class SecondRoute extends StatelessWidget {
  SecondRoute () {
    print("setting screen name as SecondScreen");
    setScreenName();
  }

  setScreenName () async {
    DengageFlutter.setNavigationWithName("SecondScreen");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal,
      appBar: AppBar(
        backgroundColor: Colors.teal[900],
        title: Text('Flutter Sample App, "Second Screen"'),
      ),
      body: Center(
        child: ElevatedButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: Text('Go back!'),
        ),
      ),
    );
  }
}