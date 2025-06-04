import 'dart:math';
import 'package:flutter/material.dart';
import 'lidar.dart';

class PointCloudPainter extends CustomPainter {
  final Map<int, Lidar> channels; // 채널별 Lidar 데이터
  final double angle; // 수평 시야각(도)
  final double vfov;  // 수직 시야각(도)

  PointCloudPainter(this.channels, this.angle, this.vfov);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = Colors.blue..strokeWidth = 2;

    final channelList = channels.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final int numChannels = channelList.length;
    if (numChannels == 0) return;

    for (int j = 0; j < numChannels; j++) {
      final lidar = channelList[j].value;
      final distances = lidar.distances;
      final int numPoints = distances.length;
      final vAngle = (-vfov / 2 + (j * vfov / numChannels)) * pi / 180;

      for (int i = 0; i < numPoints; i++) {
        final hAngle = (-angle / 2 + (i * angle / numPoints)) * pi / 180;
        final r = distances[i];
        final x = center.dx + r * cos(vAngle) * cos(hAngle);
        final y = center.dy + r * cos(vAngle) * sin(hAngle) - r * sin(vAngle);
        canvas.drawCircle(Offset(x, y), 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}