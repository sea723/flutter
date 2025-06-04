class Lidar {
  final String model;
  final int channel;
  final int pointSize;
  final double hfov;
  final List<double> vfov;
  final List<double> distances;
  final String timestamp;

  Lidar({
    required this.model,
    required this.channel,
    required this.pointSize,
    required this.hfov,
    required this.vfov,
    required this.distances,
    required this.timestamp,
  });

  factory Lidar.fromJson(Map<String, dynamic> json) {
    return Lidar(
      model: json['model'],
      channel: json['channel'],
      pointSize: json['pointsize'],
      hfov: (json['hfov'] as num).toDouble(),
      vfov: (json['vfov'] as List).map((e) => (e as num).toDouble()).toList(),
      distances: (json['distances'] as List).map((e) => (e as num).toDouble()).toList(),
      timestamp: json['timestamp'],
    );
  }
}