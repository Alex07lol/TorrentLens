import 'package:flutter/material.dart';

/// Shared loading / empty / error / offline / permission views so every screen
/// handles the same states consistently.
class LoadingView extends StatelessWidget {
  final String? label;
  const LoadingView({super.key, this.label});
  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      );
}

class EmptyView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  const EmptyView({super.key, required this.icon, required this.title, this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(message!, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView({super.key, required this.message, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 56, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 20),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
}

class OfflineView extends StatelessWidget {
  final VoidCallback? onRetry;
  const OfflineView({super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.cloud_off,
        title: 'You are offline',
        message: 'Downloads and reading work without a connection. '
            'Update checks and cloud sync will resume when you reconnect.',
        action: onRetry == null
            ? null
            : FilledButton.tonalIcon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      );
}

class PermissionDeniedView extends StatelessWidget {
  final String permission;
  final String rationale;
  final VoidCallback? onOpenSettings;
  const PermissionDeniedView({
    super.key,
    required this.permission,
    required this.rationale,
    this.onOpenSettings,
  });
  @override
  Widget build(BuildContext context) => EmptyView(
        icon: Icons.lock_outline,
        title: '$permission permission needed',
        message: rationale,
        action: onOpenSettings == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onOpenSettings, icon: const Icon(Icons.settings), label: const Text('Open settings')),
      );
}

/// A titled card used throughout the app.
class SectionCard extends StatelessWidget {
  final String? title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  const SectionCard({super.key, this.title, required this.child, this.trailing, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null)
                Row(
                  children: [
                    Expanded(child: Text(title!, style: Theme.of(context).textTheme.titleMedium)),
                    ?trailing,
                  ],
                ),
              if (title != null) const SizedBox(height: 12),
              child,
            ],
          ),
        ),
      );
}

/// A compact trust/status pill.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) Icon(icon, size: 14, color: color),
            if (icon != null) const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
