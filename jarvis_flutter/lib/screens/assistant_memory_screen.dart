import 'package:flutter/material.dart';

import '../widgets/memory_panel.dart';

class AssistantMemoryScreen extends StatelessWidget {
  const AssistantMemoryScreen({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 980;
    final topPadding = embedded && isCompact ? 78.0 : 18.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF08111B), Color(0xFF03070D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        top: embedded,
        bottom: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, topPadding, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0C2236), Color(0xFF091521)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF17324C)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Memoria do Assistente',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.92),
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Consulta a memoria persistente do assistente, filtra por tipo de registo e pesquisa entradas especificas.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Expanded(
                child: MemoryPanel(title: 'Tabela de Memoria'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
