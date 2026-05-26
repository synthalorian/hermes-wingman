import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_manager.dart';
import '../../theme/app_theme.dart';
import '../../services/hermes_api_client.dart' show BackendService;

/// Fallback providers manager — embedded in Config screen.
class FallbackSection extends StatefulWidget {
  const FallbackSection({super.key});

  @override
  State<FallbackSection> createState() => _FallbackSectionState();
}

class _FallbackSectionState extends State<FallbackSection> {
  List<String> _chain = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final backend = context.read<BackendService>();
      final data = await backend.getFallbackChain();
      if (!mounted) return;
      setState(() {
        _chain = (data['chain'] as List?)?.cast<String>() ?? [];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final scheme = context.read<ThemeManager>().currentScheme;
    final providerCtrl = TextEditingController();
    final modelCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: scheme.surface.withAlpha(235),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.borderDim.withAlpha(60)),
        ),
        title: Text('Add Fallback', style: TextStyle(color: scheme.text, fontSize: 15)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: providerCtrl,
                style: TextStyle(color: scheme.text, fontSize: 12),
                decoration: InputDecoration(
                  labelText: 'Provider (e.g. openrouter, anthropic)',
                  labelStyle: TextStyle(color: scheme.textDim, fontSize: 11),
                  filled: true, fillColor: scheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: modelCtrl,
                style: TextStyle(color: scheme.text, fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  labelText: 'Model (e.g. openrouter/auto)',
                  labelStyle: TextStyle(color: scheme.textDim, fontSize: 11),
                  filled: true, fillColor: scheme.background,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: scheme.textDim))),
          TextButton(
            onPressed: () async {
              if (providerCtrl.text.isEmpty || modelCtrl.text.isEmpty) return;
              try {
                await context.read<BackendService>().addFallback(
                    providerCtrl.text.trim(), modelCtrl.text.trim());
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (_) {}
            },
            child: Text('Add', style: TextStyle(color: scheme.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _clear() async {
    try {
      await context.read<BackendService>().clearFallback();
      _load();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.watch<ThemeManager>().currentScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.swap_vert, size: 16, color: scheme.accent),
            const SizedBox(width: 6),
            Text('Fallback Providers',
                style: TextStyle(color: scheme.text, fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            if (_chain.isNotEmpty)
              GestureDetector(
                onTap: _clear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.error.withAlpha(15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: scheme.error.withAlpha(30)),
                  ),
                  child: Text('Clear', style: TextStyle(color: scheme.error, fontSize: 9)),
                ),
              ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _add,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlpha(15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: scheme.primary.withAlpha(30)),
                ),
                child: Text('+ Add', style: TextStyle(color: scheme.primary, fontSize: 9)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))
        else if (_chain.isEmpty || (_chain.length == 1 && _chain[0].contains('No fallback')))
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.cardBackground.withAlpha(120),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim.withAlpha(30)),
            ),
            child: Text('No fallback providers configured. Primary model failures won\'t auto-retry.',
                style: TextStyle(color: scheme.textMuted, fontSize: 10)),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.cardBackground.withAlpha(120),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: scheme.borderDim.withAlpha(30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _chain)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(line,
                        style: TextStyle(color: scheme.textDim, fontSize: 10, fontFamily: 'monospace')),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
