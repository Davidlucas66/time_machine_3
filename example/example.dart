// Copyright 2018 The Time Machine Authors. All rights reserved.
// Use of this source code is governed by the Apache License 2.0, as found in the LICENSE.txt file.

import 'dart:async';

import 'dart:convert';
import 'package:resource/resource.dart';

// todo: consolidate import packages??? this seems a little much...
import 'package:time_machine/time_machine.dart';
import 'package:time_machine/time_machine_globalization.dart';
import 'package:time_machine/time_machine_text.dart';
import 'package:time_machine/time_machine_timezones.dart';

// Only needed for `await TimeMachine.initialize();`
// You only need to do this once per isolate.
// Pick the import based on your platform.
// Future Hope: This happens via conditional imports under `time_machine.dart`
import 'package:time_machine/time_machine_for_vm.dart';
// import 'package:time_machine/time_machine_for_web.dart';
// import 'package:time_machine/time_machine_for_flutter.dart';

// import 'package:time_machine/data/zones.json' as zones;

Future main() async {
  // todo: demonstrate a test clock
  // var clockForTesting = new FakeClock();

  try {
    // Sets up timezone and culture information
    await TimeMachine.initialize();
    print('Hello, ${DateTimeZone.local} from the Dart Time Machine!');

    var tzdb = await DateTimeZoneProviders.tzdb;
    var paris = await tzdb["Europe/Paris"];

    var now = SystemClock.instance.getCurrentInstant();

    print('\nBasic');
    print('UTC Time: $now');
    print('Local Time: ${now.inLocalZone()}');
    print('Paris Time: ${now.inZone(paris)}');
    
    var x = now.inLocalZone().toString();

    print('\nFormatted');
    print('UTC Time: ${now.toString('dddd yyyy-MM-dd HH:mm')}');
    print('Local Time: ${now.inLocalZone().toString('dddd yyyy-MM-dd HH:mm')}');

    var culture = await Cultures.getCulture('fr-FR');
    print('\nFormatted and French ($culture)');
    print('UTC Time: ${now.toString('dddd yyyy-MM-dd HH:mm', culture)}');
    print('Local Time: ${now.inLocalZone().toString('dddd yyyy-MM-dd HH:mm', culture)}');

    print('\nParse French Formatted DateTimeZone');
    // without the 'z' parsing will be forced to interpret the timezone as UTC
    var localText = now
        .inLocalZone()
        .toString('dddd yyyy-MM-dd HH:mm z', culture);

    var localClone = ZonedDateTimePattern
        .createWithCulture('dddd yyyy-MM-dd HH:mm z', culture)
        .parse(localText);
    print(localClone.value);
  }
  catch (error, stack) {
    print(error);
    print(stack);
  }
}