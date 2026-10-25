import 'package:flutter/material.dart';
import '../services/reading_history_service.dart';
import '../theme/app_theme.dart';

/// A card in the "Recently opened" row: the PDF's name, how far the
/// student got, and a tap target that resumes reading.
class RecentPdfCard extends StatelessWidget {
  final ReadingEntry entry;
  final VoidCallback onTap;

  const RecentPdfCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasTotal = entry.totalPages > 0;
    final progress =
        hasTotal ? (entry.lastPage / entry.totalPages).clamp(0.0, 1.0) : 0.0;

    return Container(
      width: 230,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.coral.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.picture_as_pdf_rounded,
                          color: AppColors.coral),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        entry.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                if (hasTotal)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 5,
                      color: AppColors.coral,
                      backgroundColor: AppColors.coral.withOpacity(0.15),
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  hasTotal
                      ? 'Page ${entry.lastPage} of ${entry.totalPages}'
                      : 'Tap to continue',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
