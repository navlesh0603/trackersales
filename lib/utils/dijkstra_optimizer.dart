class Node {
  final String id;
  final double lat;
  final double lng;

  Node(this.id, this.lat, this.lng);
}

class Edge {
  final Node target;
  final double weight;

  Edge(this.target, this.weight);
}

class BidirectionalDijkstra {
  final Map<String, List<Edge>> adjacencyList = {};
  final Map<String, Node> nodes = {};

  void addNode(Node node) {
    nodes[node.id] = node;
    adjacencyList[node.id] = [];
  }

  void addEdge(String sourceId, String targetId, double weight) {
    if (nodes.containsKey(sourceId) && nodes.containsKey(targetId)) {
      adjacencyList[sourceId]!.add(Edge(nodes[targetId]!, weight));
      adjacencyList[targetId]!.add(Edge(nodes[sourceId]!, weight));
    }
  }

  List<Node> findPath(String startId, String targetId) {
    if (!nodes.containsKey(startId) || !nodes.containsKey(targetId)) return [];

    final Map<String, double> distF = {startId: 0};
    final Map<String, String?> parentF = {startId: null};
    final priorityQueueF = PriorityQueue<MapEntry<String, double>>(
      (a, b) => a.value.compareTo(b.value),
    );
    priorityQueueF.add(MapEntry(startId, 0));

    final Map<String, double> distB = {targetId: 0};
    final Map<String, String?> parentB = {targetId: null};
    final priorityQueueB = PriorityQueue<MapEntry<String, double>>(
      (a, b) => a.value.compareTo(b.value),
    );
    priorityQueueB.add(MapEntry(targetId, 0));

    final Set<String> visitedF = {};
    final Set<String> visitedB = {};

    String? meetingNode;

    while (priorityQueueF.isNotEmpty && priorityQueueB.isNotEmpty) {
      final currentF = priorityQueueF.removeFirst().key;
      visitedF.add(currentF);

      if (visitedB.contains(currentF)) {
        meetingNode = currentF;
        break;
      }

      for (var edge in adjacencyList[currentF] ?? []) {
        final neighbor = edge.target.id;
        final newDist = distF[currentF]! + edge.weight;
        if (newDist < (distF[neighbor] ?? double.infinity)) {
          distF[neighbor] = newDist;
          parentF[neighbor] = currentF;
          priorityQueueF.add(MapEntry(neighbor, newDist));
        }
      }

      final currentB = priorityQueueB.removeFirst().key;
      visitedB.add(currentB);

      if (visitedF.contains(currentB)) {
        meetingNode = currentB;
        break;
      }

      for (var edge in adjacencyList[currentB] ?? []) {
        final neighbor = edge.target.id;
        final newDist = distB[currentB]! + edge.weight;
        if (newDist < (distB[neighbor] ?? double.infinity)) {
          distB[neighbor] = newDist;
          parentB[neighbor] = currentB;
          priorityQueueB.add(MapEntry(neighbor, newDist));
        }
      }
    }

    if (meetingNode == null) return [];

    List<Node> path = [];
    String? curr = meetingNode;
    while (curr != null) {
      path.insert(0, nodes[curr]!);
      curr = parentF[curr];
    }

    curr = parentB[meetingNode];
    while (curr != null) {
      path.add(nodes[curr]!);
      curr = parentB[curr];
    }

    return path;
  }
}

class PriorityQueue<T> {
  final List<T> _heap = [];
  final int Function(T, T) comparator;

  PriorityQueue(this.comparator);

  bool get isNotEmpty => _heap.isNotEmpty;

  void add(T element) {
    _heap.add(element);
    _bubbleUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) throw Exception("Queue is empty");
    final result = _heap[0];
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _sinkDown(0);
    }
    return result;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      int parentIndex = (index - 1) ~/ 2;
      if (comparator(_heap[index], _heap[parentIndex]) >= 0) break;
      _swap(index, parentIndex);
      index = parentIndex;
    }
  }

  void _sinkDown(int index) {
    while (true) {
      int leftChildIndex = 2 * index + 1;
      int rightChildIndex = 2 * index + 2;
      int smallestIndex = index;

      if (leftChildIndex < _heap.length &&
          comparator(_heap[leftChildIndex], _heap[smallestIndex]) < 0) {
        smallestIndex = leftChildIndex;
      }
      if (rightChildIndex < _heap.length &&
          comparator(_heap[rightChildIndex], _heap[smallestIndex]) < 0) {
        smallestIndex = rightChildIndex;
      }
      if (smallestIndex == index) break;
      _swap(index, smallestIndex);
      index = smallestIndex;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}
