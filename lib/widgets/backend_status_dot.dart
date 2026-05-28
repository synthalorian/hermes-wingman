import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hermes_wingman/services/hermes_api_client.dart';
import 'package:hermes_wingman/theme/app_theme.dart';

class BackendStatusDot extends StatelessWidget {
  final AppColorScheme scheme;
  final BackendConnectionState state;
  final double dotSize;

  const BackendStatusDot({
    super.key,
    required this.scheme,
    required this.state,
    this.dotSize = 8,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    String tooltip;
    switch (state) {
      case BackendConnectionState.connected:
        color = scheme.success;
        tooltip = 'Backend connected';
      case BackendConnectionState.initializing:
        color = scheme.warning;
        tooltip = 'Backend initializing...';
      case BackendConnectionState.failed:
      case BackendConnectionState.notFound:
        color = scheme.error;
        tooltip = 'Backend offline: ${context.read<BackendService>().lastError ?? "unknown"}';
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        width: dotSize,
        height: dotSize,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color.withAlpha(153), blurRadius: 6, spreadRadius: 1),
          ],
        ),
      ),
    );
  }
}
