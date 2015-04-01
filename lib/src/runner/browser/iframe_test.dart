// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library test.runner.browser.iframe_test;

import '../../backend/live_test.dart';
import '../../backend/live_test_controller.dart';
import '../../backend/metadata.dart';
import '../../backend/state.dart';
import '../../backend/suite.dart';
import '../../backend/test.dart';
import '../../util/multi_channel.dart';
import '../../util/remote_exception.dart';

/// A test in a running iframe.
class IframeTest implements Test {
  final String name;
  final Metadata metadata;

  /// The channel used to communicate with the test's [IframeListener].
  final MultiChannel _channel;

  IframeTest(this.name, this.metadata, this._channel);

  LiveTest load(Suite suite) {
    var controller;
    controller = new LiveTestController(suite, this, () {
      controller.setState(const State(Status.running, Result.success));

      var testChannel = _channel.virtualChannel();
      _channel.sink.add({
        'command': 'run',
        'channel': testChannel.id
      });

      testChannel.stream.listen((message) {
        if (message['type'] == 'error') {
          var asyncError = RemoteException.deserialize(message['error']);
          controller.addError(asyncError.error, asyncError.stackTrace);
        } else if (message['type'] == 'state-change') {
          controller.setState(
              new State(
                  new Status.parse(message['status']),
                  new Result.parse(message['result'])));
        } else if (message['type'] == 'print') {
          controller.print(message['line']);
        } else {
          assert(message['type'] == 'complete');
          controller.completer.complete();
        }
      });
    });
    return controller.liveTest;
  }
}
