import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/pikachu_loader.dart';
import '../../usecase/home_notifier.dart';

const _gateCapDuration = Duration(seconds: 3);

/// Ports `components/home/home-loading-gate.tsx` — a full-screen Pikachu
/// animation shown once while the home page's initial data loads, capped at
/// 3s so a slow connection never blocks the gate forever.
class HomeLoadingGate extends ConsumerStatefulWidget {
  const HomeLoadingGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<HomeLoadingGate> createState() => _HomeLoadingGateState();
}

class _HomeLoadingGateState extends ConsumerState<HomeLoadingGate> {
  bool _gateOpen = false;
  Timer? _capTimer;

  @override
  void initState() {
    super.initState();
    _capTimer = Timer(_gateCapDuration, _openGate);
  }

  @override
  void dispose() {
    _capTimer?.cancel();
    super.dispose();
  }

  void _openGate() {
    if (_gateOpen) return;
    _capTimer?.cancel();
    setState(() => _gateOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(explorePacksProvider, (previous, next) {
      if (!next.isLoading) _openGate();
    });

    return Stack(
      children: [
        widget.child,
        if (!_gateOpen)
          Positioned.fill(
            child: ColoredBox(
              color: context.appColors.surface,
              child: const PikachuLoader(size: 180),
            ),
          ),
      ],
    );
  }
}
