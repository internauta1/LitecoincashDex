import 'package:flutter/material.dart';
import 'package:web_dex/app_config/app_config.dart';

// Preserved for compatibility with existing imports.
const Color gleecPurple = Color(0xFF21B84B);

const Color lccDexGreen = Color(0xFF21B84B);

/// LCC DEX logo. The original class name is retained for compatibility.
class GleecDexLogo extends StatelessWidget {
  const GleecDexLogo({
    super.key,
    this.height = 32,
    this.themeMode,
    this.isDense = false,
  });

  final double height;
  final ThemeMode? themeMode;
  final bool isDense;

  @override
  Widget build(BuildContext context) {
    final isDarkTheme = themeMode == null
        ? Theme.of(context).brightness == Brightness.dark
        : themeMode == ThemeMode.dark;

    final textColor = isDarkTheme ? Colors.white : Colors.black87;

    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Image.asset(
            '$assetsPath/logo/logo.png',
            width: height,
            height: height,
            fit: BoxFit.contain,
          ),
          SizedBox(width: isDense ? 9 : 12),
          Text(
            'LCC',
            style: TextStyle(
              color: textColor,
              fontFamily: 'Rubik',
              fontWeight: FontWeight.w700,
              fontSize: height * 0.70,
              height: 1,
            ),
          ),
          SizedBox(width: isDense ? 5 : 7),
          Text(
            'DEX',
            style: TextStyle(
              color: lccDexGreen,
              fontFamily: 'Rubik',
              fontWeight: FontWeight.w600,
              fontSize: height * 0.70,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}