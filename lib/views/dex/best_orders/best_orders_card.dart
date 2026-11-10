import 'package:app_theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:web_dex/shared/ui/gradient_border.dart';

/// The same plate and border used by the DEX form and order book.
class BestOrdersCard extends StatelessWidget {
  const BestOrdersCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide.none,
    );
    final fieldText = base.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      color: base.colorScheme.onSurface,
    );
    return GradientBorder(
      innerColor: dexPageColors.frontPlate,
      gradient: dexPageColors.formPlateGradient,
      child: Theme(
        data: base.copyWith(
          textTheme: base.textTheme.copyWith(
            bodyLarge: fieldText,
            bodyMedium: fieldText,
            bodySmall: base.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: dexPageColors.inactiveText,
            ),
          ),
          inputDecorationTheme: base.inputDecorationTheme.copyWith(
            filled: true,
            fillColor: dexPageColors.frontPlateInner,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: border,
            disabledBorder: border,
            focusedBorder: border.copyWith(
              borderSide: BorderSide(color: base.primaryColor),
            ),
            hintStyle: fieldText?.copyWith(color: dexPageColors.inactiveText),
            helperStyle: base.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: dexPageColors.inactiveText,
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: (base.textButtonTheme.style ?? const ButtonStyle()).copyWith(
              textStyle: WidgetStatePropertyAll(
                base.textTheme.labelLarge?.copyWith(fontSize: 14),
              ),
            ),
          ),
        ),
        child: DefaultTextStyle.merge(
          style: TextStyle(fontSize: 14, color: base.colorScheme.onSurface),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonHideUnderline(child: child),
          ),
        ),
      ),
    );
  }
}
