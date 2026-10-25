import 'package:flutter/material.dart';
import '../models/drive_node.dart';
import '../theme/app_theme.dart';

/// A folder shown in search results. Styled like [FileTile] so results
/// read as one consistent list.
class FolderResultTile extends StatelessWidget {
  final DriveNode node;
  final String? location;
  final VoidCallback onTap;

  const FolderResultTile({
    super.key,
    required this.node,
    this.location,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.gradientFor(node.name);
    final hasLocation = location != null && location!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
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
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.folder_rounded, color: Colors.white),
        ),
        title: Text(node.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          hasLocation ? 'Folder · $location' : 'Folder',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: Colors.grey[500]),
        onTap: onTap,
      ),
    );
  }
}
