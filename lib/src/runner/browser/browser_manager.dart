// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.runner.browser.browser_manager;

import 'dart:async';
import 'dart:convert';

import 'package:http_parser/http_parser.dart';

import '../../backend/metadata.dart';
import '../../backend/suite.dart';
import '../../util/multi_channel.dart';
import '../../util/remote_exception.dart';
import '../../utils.dart';
import '../load_exception.dart';
import 'iframe_test.dart';

/// A class that manages the connection to a single running browser.
///
/// This is in charge of telling the browser which test suites to load and
/// converting its responses into [Suite] objects.
class BrowserManager {
  /// The channel used to communicate with the browser.
  ///
  /// This is connected to a page running `static/host.dart`.
  final MultiChannel _channel;

  /// Creates a new BrowserManager that communicates with a browser over
  /// [webSocket].
  BrowserManager(CompatibleWebSocket webSocket)
      : _channel = new MultiChannel(
          webSocket.map(JSON.decode),
          mapSink(webSocket, JSON.encode));

  /// Tells the browser the load a test suite from the URL [url].
  ///
  /// [url] should be an HTML page with a reference to the JS-compiled test
  /// suite. [path] is the path of the original test suite file, which is used
  /// for reporting.
  Future<Suite> loadSuite(String path, Uri url) {
    var suiteChannel = _channel.virtualChannel();
    _channel.sink.add({
      "command": "loadSuite",
      "url": url.toString(),
      "channel": suiteChannel.id
    });

    // Create a nested MultiChannel because the iframe will be using a channel
    // wrapped within the host's channel.
    suiteChannel = new MultiChannel(suiteChannel.stream, suiteChannel.sink);
    return suiteChannel.stream.first.then((response) {
      if (response["type"] == "loadException") {
        return new Future.error(new LoadException(path, response["message"]));
      } else if (response["type"] == "error") {
        var asyncError = RemoteException.deserialize(response["error"]);
        return new Future.error(
            new LoadException(path, asyncError.error),
            asyncError.stackTrace);
      }

      return new Suite(response["tests"].map((test) {
        var metadata = new Metadata.deserialize(test['metadata']);
        var testChannel = suiteChannel.virtualChannel(test['channel']);
        return new IframeTest(test['name'], metadata, testChannel);
      }), path: path, platform: "Chrome");
    });
  }
}
