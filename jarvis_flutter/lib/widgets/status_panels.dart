import 'package:flutter/material.dart';

import 'log_panel.dart';
import 'memory_panel.dart';

class StatusPanels extends StatelessWidget {
  const StatusPanels({super.key});

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 900;

    if (isWide) {
      return const Column(
        children: [
          Expanded(child: LogPanel()),
          SizedBox(height: 12),
          Expanded(child: MemoryPanel()),
        ],
      );
    }

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.32),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.18)),
            ),
            padding: const EdgeInsets.all(4),
            child: const TabBar(
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicator: BoxDecoration(
                color: Color(0x2200E5FF),
                borderRadius: BorderRadius.all(Radius.circular(999)),
              ),
              tabs: [
                Tab(text: 'Logs'),
                Tab(text: 'Memoria'),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Expanded(
            child: TabBarView(
              children: [
                LogPanel(),
                MemoryPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
