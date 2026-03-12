import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:trackersales/utils/dijkstra_optimizer.dart';

class RoutingService {
  final BidirectionalDijkstra _optimizer = BidirectionalDijkstra();

  RoutingService() {
    _loadMockRoadGraph();
  }

  void _loadMockRoadGraph() {
    // Adding mock nodes (nodes representing road intersections)
    final nodes = [
      Node("A", 19.0760, 72.8777), // Mumbai Point 1
      Node("B", 19.0800, 72.8850), // Mumbai Point 2
      Node("C", 19.0900, 72.8900), // Mumbai Point 3
      Node("D", 19.1000, 72.9000), // Mumbai Point 4
      Node("E", 19.1100, 72.9100), // Mumbai Point 5
    ];

    for (var node in nodes) {
      _optimizer.addNode(node);
    }

    // Adding mock edges (roads connecting intersections with weights/distances)
    _optimizer.addEdge("A", "B", 1.2);
    _optimizer.addEdge("B", "C", 2.5);
    _optimizer.addEdge("C", "D", 1.8);
    _optimizer.addEdge("D", "E", 3.1);
    _optimizer.addEdge("A", "C", 4.0);
  }

  List<LatLng> getOptimizedRoute(String startId, String endId) {
    final path = _optimizer.findPath(startId, endId);
    return path.map((node) => LatLng(node.lat, node.lng)).toList();
  }
}
