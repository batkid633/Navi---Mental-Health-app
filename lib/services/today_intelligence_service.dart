import 'package:flutter/material.dart';
import 'package:navi_personal/models/today_state.dart';


class TodayIntelligenceService {
  static TodayMoodTrend classify({
    required double today,
    required double rollingAvg,
    required double volatility,
    required double momentum,
  }) {
    if (volatility > 0.25) {
      return TodayMoodTrend.volatile;
    }

    if (momentum > 0.05) {
      return TodayMoodTrend.improving;
    }

    if (momentum < -0.05) {
      return TodayMoodTrend.declining;
    }

    if (rollingAvg > 0.2) {
      return TodayMoodTrend.stablePositive;
    }

    if (rollingAvg < -0.2) {
      return TodayMoodTrend.stableNegative;
    }

    return TodayMoodTrend.stableNeutral;
  }
  static String insightText(TodayMoodTrend state) {
  switch (state) {
    case TodayMoodTrend.stablePositive:
      return "You're in a steady, positive emotional state today.";
    case TodayMoodTrend.stableNeutral:
      return "You're emotionally steady today.";
    case TodayMoodTrend.stableNegative:
      return "You're feeling consistently low today.";
    case TodayMoodTrend.improving:
      return "Your mood has been improving recently.";
    case TodayMoodTrend.declining:
      return "Your mood has been trending downward.";
    case TodayMoodTrend.volatile:
      return "Your emotions have been fluctuating a lot recently.";
  }
}
static String volatilityLabel(double volatility) {
  if (volatility < 0.15) {
    return "Stable";
  } else if (volatility < 0.35) {
    return "Variable";
  } else {
    return "Turbulent";
  }
}
static Color volatilityColor(double volatility) {
  if (volatility < 0.15) {
    return Colors.green;
  } else if (volatility < 0.35) {
    return Colors.orange;
  } else {
    return Colors.red;
  }
}
static String momentumLabel(double momentum) {
  if (momentum > 0.1) {
    return "Improving";
  } else if (momentum < -0.1) {
    return "Declining";
  } else {
    return "Flat";
  }
}
static Color momentumColor(double momentum) {
  if (momentum > 0.1) {
    return Colors.green;
  } else if (momentum < -0.1) {
    return Colors.red;
  } else {
    return Colors.grey;
  }
}
static Color stateColor(TodayMoodTrend state) {
  switch (state) {
    case TodayMoodTrend.stablePositive:
      return Colors.green;
    case TodayMoodTrend.improving:
      return Colors.lightGreen;
    case TodayMoodTrend.stableNeutral:
      return Colors.blueGrey;
    case TodayMoodTrend.declining:
      return Colors.orange;
    case TodayMoodTrend.stableNegative:
      return Colors.redAccent;
    case TodayMoodTrend.volatile:
      return Colors.purple;
  }
}

}
