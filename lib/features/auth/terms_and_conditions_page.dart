import 'package:flutter/material.dart';
import 'terms_content.dart';

class TermsAndConditionsPage extends StatefulWidget {
  const TermsAndConditionsPage({super.key});

  static const routeName = '/terms-and-conditions';

  @override
  State<TermsAndConditionsPage> createState() => _TermsAndConditionsPageState();
}

class _TermsAndConditionsPageState extends State<TermsAndConditionsPage> {
  static const _gold = Color(0xFFEAB308);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = (constraints.maxWidth - 32).clamp(0.0, 560.0);
            final panelHeight = (constraints.maxHeight - 32).clamp(0.0, 760.0);

            return Center(
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.10),
                        blurRadius: 32,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _buildHeader(context),
                      Expanded(
                        child: SelectionArea(
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                            itemCount: eventHubTerms.length,
                            itemBuilder: (context, index) =>
                                _buildSection(index),
                          ),
                        ),
                      ),
                      _buildFooter(context),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFF8F9FC),
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _gold.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.gavel_rounded, color: _gold, size: 20),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Terms and Conditions',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
                Text(
                  'J-Jireh EventHub · Updated October 2026',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 11,
                    color: Color(0xFF858B98),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close terms',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF858B98)),
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 18),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
          child: const Text(
            'Close',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(int index) {
    final section = eventHubTerms[index];

    return Padding(
      padding: EdgeInsets.only(bottom: index == eventHubTerms.length - 1 ? 0 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(section.icon, size: 15, color: _gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    height: 1.4,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A2E),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 23),
            child: Text(
              section.body,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                height: 1.6,
                color: Color(0xFF646B78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}