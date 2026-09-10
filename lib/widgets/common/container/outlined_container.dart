import 'package:anx_reader/theme/anx_ui_tokens.dart';
import 'package:anx_reader/widgets/common/container/base_rounded_container.dart';
import 'package:flutter/material.dart';

class OutlinedContainer extends BaseRoundedContainer {
  const OutlinedContainer({
    super.key,
    required super.child,
    super.width,
    super.height,
    super.padding,
    super.margin,
    super.radius,
    super.constraints,
    super.animationDuration,
    super.animationCurve,
    this.color,
    this.outlineColor,
  });

  final Color? color;
  final Color? outlineColor;

  @override
  ShapeDecoration decoration(
    BuildContext context,
    BorderRadiusGeometry borderRadius,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return buildShapeDecoration(
      color: color ?? scheme.surface,
      borderSide: BorderSide(
        color: outlineColor ?? AnxUiTokens.quietBorder(scheme),
        width: 0.8,
        strokeAlign: BorderSide.strokeAlignOutside,
      ),
      borderRadius: borderRadius,
    );
  }
}
