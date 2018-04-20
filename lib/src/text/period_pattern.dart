import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:quiver_hashcode/hashcode.dart';

import 'package:time_machine/time_machine.dart';
import 'package:time_machine/time_machine_utilities.dart';
import 'package:time_machine/time_machine_calendars.dart';
import 'package:time_machine/time_machine_timezones.dart';
import 'package:time_machine/time_machine_text.dart';

/// <summary>
/// Represents a pattern for parsing and formatting <see cref="Period"/> values.
/// </summary>
/// <threadsafety>This type is immutable reference type. See the thread safety section of the user guide for more information.</threadsafety>
@immutable
/*sealed*/ class PeriodPattern implements IPattern<Period> {
  /// <summary>
  /// Pattern which uses the normal ISO format for all the supported ISO
  /// fields, but extends the time part with "s" for milliseconds, "t" for ticks and "n" for nanoseconds.
  /// No normalization is carried out, and a period may contain weeks as well as years, months and days.
  /// Each element may also be negative, independently of other elements. This pattern round-trips its
  /// values: a parse/format cycle will produce an identical period, including units.
  /// </summary>
  /// <value>
  /// Pattern which uses the normal ISO format for all the supported ISO
  /// fields, but extends the time part with "s" for milliseconds, "t" for ticks and "n" for nanoseconds.
  /// </value>
  static final PeriodPattern Roundtrip = new PeriodPattern(new _RoundtripPatternImpl());

  /// <summary>
  /// A "normalizing" pattern which abides by the ISO-8601 duration format as far as possible.
  /// Weeks are added to the number of days (after multiplying by 7). Time units are normalized
  /// (extending into days where necessary), and fractions of seconds are represented within the
  /// seconds part. Unlike ISO-8601, which pattern allows for negative values within a period.
  /// </summary>
  /// <remarks>
  /// Note that normalizing the period when formatting will cause an <see cref="System.OverflowException"/>
  /// if the period contains more than <see cref="System.Int64.MaxValue"/> ticks when the
  /// combined weeks/days/time portions are considered. Such a period could never
  /// be useful anyway, however.
  /// </remarks>
  /// <value>A "normalizing" pattern which abides by the ISO-8601 duration format as far as possible.</value>
  static final PeriodPattern NormalizingIso = new PeriodPattern(new _NormalizingIsoPatternImpl());

  @private final IPattern<Period> pattern;

  @private PeriodPattern(IPattern<Period> pattern) : this.pattern = Preconditions.checkNotNull(pattern, 'pattern');

  /// <summary>
  /// Parses the given text value according to the rules of this pattern.
  /// </summary>
  /// <remarks>
  /// This method never throws an exception (barring a bug in Noda Time itself). Even errors such as
  /// the argument being null are wrapped in a parse result.
  /// </remarks>
  /// <param name="text">The text value to parse.</param>
  /// <returns>The result of parsing, which may be successful or unsuccessful.</returns>
  ParseResult<Period> Parse(String text) => pattern.Parse(text);

  /// <summary>
  /// Formats the given period as text according to the rules of this pattern.
  /// </summary>
  /// <param name="value">The period to format.</param>
  /// <returns>The period formatted according to this pattern.</returns>
  String Format(Period value) => pattern.Format(value);

  /// <summary>
  /// Formats the given value as text according to the rules of this pattern,
  /// appending to the given <see cref="StringBuffer"/>.
  /// </summary>
  /// <param name="value">The value to format.</param>
  /// <param name="builder">The <c>StringBuffer</c> to append to.</param>
  /// <returns>The builder passed in as <paramref name="builder"/>.</returns>
  StringBuffer AppendFormat(Period value, StringBuffer builder) => pattern.AppendFormat(value, builder);

  @private static void AppendValue(StringBuffer builder, int value, String suffix) {
    // Avoid having a load of conditions in the calling code by checking here
    if (value == 0) {
      return;
    }
    FormatHelper.FormatInvariant(value, builder);
    builder.write(suffix);
  }

  @private static ParseResult<Period> InvalidUnit(ValueCursor cursor, String unitCharacter) =>
      ParseResult.ForInvalidValue<Period>(cursor, TextErrorMessages.InvalidUnitSpecifier, [unitCharacter]);

  @private static ParseResult<Period> RepeatedUnit(ValueCursor cursor, String unitCharacter) =>
      ParseResult.ForInvalidValue<Period>(cursor, TextErrorMessages.RepeatedUnitSpecifier, [unitCharacter]);

  @private static ParseResult<Period> MisplacedUnit(ValueCursor cursor, String unitCharacter) =>
      ParseResult.ForInvalidValue<Period>(cursor, TextErrorMessages.MisplacedUnitSpecifier, [unitCharacter]);
}

@private /*sealed*/ class _RoundtripPatternImpl implements IPattern<Period> {
  ParseResult<Period> Parse(String text) {
    if (text == null) {
      return ParseResult.ArgumentNull<Period>("text");
    }
    if (text.length == 0) {
      return ParseResult.ValueStringEmpty;
    }

    ValueCursor valueCursor = new ValueCursor(text);

    valueCursor.MoveNext();
    if (valueCursor.Current != 'P') {
      return ParseResult.MismatchedCharacter<Period>(valueCursor, 'P');
    }
    bool inDate = true;
    PeriodBuilder builder = new PeriodBuilder();
    PeriodUnits unitsSoFar = PeriodUnits.none;
    while (valueCursor.MoveNext()) {
      var unitValue = new OutBox(0);
      if (inDate && valueCursor.Current == 'T') {
        inDate = false;
        continue;
      }
      var failure = valueCursor.ParseInt64<Period>(unitValue);
      if (failure != null) {
        return failure;
      }
      if (valueCursor.Length == valueCursor.Index) {
        return ParseResult.EndOfString<Period>(valueCursor);
      }
      // Various failure cases:
      // - Repeated unit (e.g. P1M2M)
      // - Time unit is in date part (e.g. P5M)
      // - Date unit is in time part (e.g. PT1D)
      // - Unit is in incorrect order (e.g. P5D1Y)
      // - Unit is invalid (e.g. P5J)
      // - Unit is missing (e.g. P5)
      PeriodUnits unit;
      switch (valueCursor.Current) {
        case 'Y':
          unit = PeriodUnits.years;
          break;
        case 'M':
          unit = inDate ? PeriodUnits.months : PeriodUnits.minutes;
          break;
        case 'W':
          unit = PeriodUnits.weeks;
          break;
        case 'D':
          unit = PeriodUnits.days;
          break;
        case 'H':
          unit = PeriodUnits.hours;
          break;
        case 'S':
          unit = PeriodUnits.seconds;
          break;
        case 's':
          unit = PeriodUnits.milliseconds;
          break;
        case 't':
          unit = PeriodUnits.ticks;
          break;
        case 'n':
          unit = PeriodUnits.nanoseconds;
          break;
        default:
          return PeriodPattern.InvalidUnit(valueCursor, valueCursor.Current);
      }
      if ((unit & unitsSoFar) != 0) {
        return PeriodPattern.RepeatedUnit(valueCursor, valueCursor.Current);
      }

      // This handles putting months before years, for example. Less significant units
      // have higher integer representations.
      if (unit < unitsSoFar) {
        return PeriodPattern.MisplacedUnit(valueCursor, valueCursor.Current);
      }
      // The result of checking "there aren't any time units in this unit" should be
      // equal to "we're still in the date part".
      if (((unit & PeriodUnits.allTimeUnits).value == 0) != inDate) {
        return PeriodPattern.MisplacedUnit(valueCursor, valueCursor.Current);
      }
      builder[unit] = unitValue.value;
      unitsSoFar |= unit;
    }
    return ParseResult.ForValue<Period>(builder.Build());
  }

  String Format(Period value) => AppendFormat(value, new StringBuffer()).toString();

  StringBuffer AppendFormat(Period value, StringBuffer builder) {
    Preconditions.checkNotNull(value, 'value');
    Preconditions.checkNotNull(builder, 'builder');
    builder.write("P");
    PeriodPattern.AppendValue(builder, value.Years, "Y");
    PeriodPattern.AppendValue(builder, value.Months, "M");
    PeriodPattern.AppendValue(builder, value.Weeks, "W");
    PeriodPattern.AppendValue(builder, value.Days, "D");
    if (value.HasTimeComponent) {
      builder.write("T");
      PeriodPattern.AppendValue(builder, value.Hours, "H");
      PeriodPattern.AppendValue(builder, value.Minutes, "M");
      PeriodPattern.AppendValue(builder, value.Seconds, "S");
      PeriodPattern.AppendValue(builder, value.Milliseconds, "s");
      PeriodPattern.AppendValue(builder, value.Ticks, "t");
      PeriodPattern.AppendValue(builder, value.Nanoseconds, "n");
    }
    return builder;
  }
}

@private /*sealed*/ class _NormalizingIsoPatternImpl implements IPattern<Period> {
// TODO(misc): Tidy this up a *lot*.
  ParseResult<Period> Parse(String text) {
    if (text == null) {
      return ParseResult.ArgumentNull<Period>("text");
    }
    if (text.length == 0) {
      return ParseResult.ValueStringEmpty;
    }

    ValueCursor valueCursor = new ValueCursor(text);

    valueCursor.MoveNext();
    if (valueCursor.Current != 'P') {
      return ParseResult.MismatchedCharacter<Period>(valueCursor, 'P');
    }
    bool inDate = true;
    PeriodBuilder builder = new PeriodBuilder();
    PeriodUnits unitsSoFar = PeriodUnits.none;
    while (valueCursor.MoveNext()) {
      OutBox unitValue = new OutBox(0);
      if (inDate && valueCursor.Current == 'T') {
        inDate = false;
        continue;
      }
      bool negative = valueCursor.Current == '-';
      var failure = valueCursor.ParseInt64<Period>(unitValue);
      if (failure != null) {
        return failure;
      }
      if (valueCursor.Length == valueCursor.Index) {
        return ParseResult.EndOfString<Period>(valueCursor);
      }
      // Various failure cases:
      // - Repeated unit (e.g. P1M2M)
      // - Time unit is in date part (e.g. P5M)
      // - Date unit is in time part (e.g. PT1D)
      // - Unit is in incorrect order (e.g. P5D1Y)
      // - Unit is invalid (e.g. P5J)
      // - Unit is missing (e.g. P5)
      PeriodUnits unit;
      switch (valueCursor.Current) {
        case 'Y':
          unit = PeriodUnits.years;
          break;
        case 'M':
          unit = inDate ? PeriodUnits.months : PeriodUnits.minutes;
          break;
        case 'W':
          unit = PeriodUnits.weeks;
          break;
        case 'D':
          unit = PeriodUnits.days;
          break;
        case 'H':
          unit = PeriodUnits.hours;
          break;
        case 'S':
          unit = PeriodUnits.seconds;
          break;
        case ',':
        case '.':
          unit = PeriodUnits.nanoseconds;
          break; // Special handling below
        default:
          return PeriodPattern.InvalidUnit(valueCursor, valueCursor.Current);
      }
      if ((unit.value & unitsSoFar.value) != 0) {
        return PeriodPattern.RepeatedUnit(valueCursor, valueCursor.Current);
      }

      // This handles putting months before years, for example. Less significant units
      // have higher integer representations.
      if (unit < unitsSoFar) {
        return PeriodPattern.MisplacedUnit(valueCursor, valueCursor.Current);
      }

      // The result of checking "there aren't any time units in this unit" should be
      // equal to "we're still in the date part".
      if (((unit.value & PeriodUnits.allTimeUnits.value) == 0) != inDate) {
        return PeriodPattern.MisplacedUnit(valueCursor, valueCursor.Current);
      }

      // Seen a . or , which need special handling.
      if (unit == PeriodUnits.nanoseconds) {
        // Check for already having seen seconds, e.g. PT5S0.5
        if ((unitsSoFar & PeriodUnits.seconds) != 0) {
          return PeriodPattern.MisplacedUnit(valueCursor, valueCursor.Current);
        }
        builder.Seconds = unitValue.value;

        if (!valueCursor.MoveNext()) {
          return ParseResult.MissingNumber<Period>(valueCursor);
        }
        int totalNanoseconds = valueCursor.ParseFraction(9, 9, 1);
        // Can cope with at most 999999999 nanoseconds
        if (totalNanoseconds == null) {
          return ParseResult.MissingNumber<Period>(valueCursor);
        }
        // Use whether or not the seconds value was negative (even if 0)
        // as the indication of whether this value is negative.
        if (negative) {
          totalNanoseconds = -totalNanoseconds;
        }
        builder.Milliseconds = (totalNanoseconds ~/ TimeConstants.nanosecondsPerMillisecond) % TimeConstants.millisecondsPerSecond;
        builder.Ticks = (totalNanoseconds ~/ TimeConstants.nanosecondsPerTick) % TimeConstants.ticksPerMillisecond;
        builder.Nanoseconds = totalNanoseconds % TimeConstants.nanosecondsPerTick;

        if (valueCursor.Current != 'S') {
          return ParseResult.MismatchedCharacter<Period>(valueCursor, 'S');
        }
        if (valueCursor.MoveNext()) {
          return ParseResult.ExpectedEndOfString<Period>(valueCursor);
        }
        return ParseResult.ForValue<Period>(builder.Build());
      }

      builder[unit] = unitValue.value;
      unitsSoFar |= unit;
    }
    if (unitsSoFar.value == 0) {
      return ParseResult.ForInvalidValue<Period>(valueCursor, TextErrorMessages.EmptyPeriod);
    }
    return ParseResult.ForValue<Period>(builder.Build());
  }

  String Format(Period value) => AppendFormat(value, new StringBuffer()).toString();

  StringBuffer AppendFormat(Period value, StringBuffer builder) {
    Preconditions.checkNotNull(value, 'value');
    Preconditions.checkNotNull(builder, 'builder');
    value = value.Normalize();
    // Always ensure we've got *some* unit; arbitrarily pick days.
    if (value.Equals(Period.Zero)) {
      builder.write("P0D");
      return builder;
    }
    builder.write("P");
    PeriodPattern.AppendValue(builder, value.Years, "Y");
    PeriodPattern.AppendValue(builder, value.Months, "M");
    PeriodPattern.AppendValue(builder, value.Weeks, "W");
    PeriodPattern.AppendValue(builder, value.Days, "D");
    if (value.HasTimeComponent) {
      builder.write("T");
      PeriodPattern.AppendValue(builder, value.Hours, "H");
      PeriodPattern.AppendValue(builder, value.Minutes, "M");
      int nanoseconds = value.Milliseconds * TimeConstants.nanosecondsPerMillisecond + value.Ticks * TimeConstants.nanosecondsPerTick + value.Nanoseconds;
      int seconds = value.Seconds;
      if (nanoseconds != 0 || seconds != 0) {
        if (nanoseconds < 0 || seconds < 0) {
          builder.write("-");
          nanoseconds = -nanoseconds;
          seconds = -seconds;
        }
        FormatHelper.FormatInvariant(seconds, builder);
        if (nanoseconds != 0) {
          builder.write(".");
          FormatHelper.AppendFractionTruncate(nanoseconds, 9, 9, builder);
        }
        builder.write("S");
      }
    }
    return builder;
  }
}