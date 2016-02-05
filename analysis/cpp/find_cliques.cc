// Copyright 2014 Google Inc. All rights reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <assert.h>
#include <stdarg.h>  // va_list, etc.
#include <stdio.h>
#include <stdint.h>  // uint16_t
#include <string>
// Using unordered_{set,map} and not the older set,map since they only require
// implementing equality, not comparison.  They require a C++ 11 compiler.
#include <unordered_map>
#include <unordered_set>
#include <vector>

// find_cliques.cc: Find k-cliques in a k-partite graph.  This is part of the
// RAPPOR analysis for unknown dictionaries.
//
// A clique is a complete subgraph; it has (|N| choose 2) edges.
//
// This does the same computation as FindFeasibleStrings in
// analysis/R/decode_ngrams.R.

// Graph format:
//
// num_partitions 3
// 0.ab 1.bc
// 0.ab 2.de
//
// See WriteKPartiteGraph in analysis/R/decode_ngrams.R for details.
//
// PERFORMANCE
//
// The code is optimized in terms of memory locality.  Nodes are 4 bytes; Edges
// are 8 bytes; PathArray is a contiguous block of memory.

using std::unordered_map;
using std::unordered_set;
using std::string;
using std::vector;

// TODO: log to stderr.  Add VERBOSE logging.
void log(const char* fmt, ...) {
  va_list args;
  va_start(args, fmt);
  vprintf(fmt, args);
  va_end(args);
  printf("\n");
}

// Nodes and Edges are value types.  A node is 4 bytes.  2^16 = 65536
// partitions is plenty.
struct Node {
  uint16_t partition;
  // Right now we support bigrams.  We may want to support trigrams or
  // arbitrary n-grams, although there will be a performance hit.
  char ngram[2];

  // for debugging only
  string ToString() const {
    char buf[100];
    snprintf(buf, sizeof(buf), "%d.%c%c", partition, ngram[0], ngram[1]);
    return string(buf);  // copies buf
  }
};

// Implement hash and equality functors for unordered_set.
struct NodeHash {
  int operator() (const Node& node) const {
    // DJB hash: http://floodyberry.com/noncryptohashzoo/DJB.html
    int h = 5381;
    h = (h << 5) + h + node.partition;
    h = (h << 5) + h + node.ngram[0];
    h = (h << 5) + h + node.ngram[1];
    // log("hash %s = %d", node.ToString().c_str(), h);
    return h;
  }
};

struct NodeEq {
  bool operator() (const Node& x, const Node& y) const {
    // TODO: optimize to 4 byte comparison with memcmp(&x, &y, sizeof(Node))?
    // NOTE: x.ngram == y.ngram is wrong; it compares pointers!
    return x.partition == y.partition &&
           x.ngram[0] == y.ngram[0] &&
           x.ngram[1] == y.ngram[1];
  }
};

// This is an undirected edge, but we still call them "left" and "right"
// because the partition of "left" must be less than that of "right".
//
// NOTE: To reduce the size further, we could have a NodePool, and then typedef
// uint16_t NodeId.  Edge and Path can both use a 2 byte NodeId instead of a 4
// byte Node.  ToString() can take the NodePool for pretty printing.
//
// This will be better for the EnumeratePaths stage, but it will be
// worse for the CheckForCliques stage (doing the lookups may reduce memory
// locality).

struct Edge {
  Node left;
  Node right;

  // for debugging only
  string ToString() const {
    return left.ToString() + " - " + right.ToString();
  }
};

// Implement hash and equality functors for unordered_set.
struct EdgeHash {
  int operator() (const Edge& edge) const {
    // DJB hash
    int h = 5381;
    h = (h << 5) + h + NodeHash()(edge.left);
    h = (h << 5) + h + NodeHash()(edge.right);
    return h;
  }
};

struct EdgeEq {
  bool operator() (const Edge& x, const Edge& y) const {
    // TODO: optimize to 8 byte comparison with memcmp(&x, &y, sizeof(Edge))?
    // This is in the inner loop for removing cadidates.
    return NodeEq()(x.left, y.left) && NodeEq()(x.right, y.right);
  }
};

typedef unordered_set<Edge, EdgeHash, EdgeEq> EdgeSet;

// The full graph.  It is k-partite, which can be seen by the node naming
// convention.
struct Graph {
  int num_partitions;
  vector<Edge> edges;
};

// Given a Node, look up Nodes in the adjacent partition that it is connected
// to.
typedef unordered_map<Node, vector<Node>, NodeHash, NodeEq> Adjacency;

// for debugging only
string AdjacencyToString(const Adjacency& a) {
  string s;
  for (auto& kv : a) {
    s += kv.first.ToString();
    s += " : <";
    for (auto& node : kv.second) {
      s += node.ToString();
      s += " ";
    }
    s += ">  ";
  }
  return s;
}

// Subgraph where only edges between adjacent partitions are included.
//
// We have k partitions, numbered 0 to k-1.  This means we have k-1 "columns",
// numbered 0 to k-2.
//
// A column is subgraph containing edges between adjacent partitions of the
// k-partite graph.
//
// The ColumnSubgraph class represents ALL columns (and is itself a subgraph).

class ColumnSubgraph {
 public:
  explicit ColumnSubgraph(int num_columns)
      : num_columns_(num_columns),
        adj_list_(new Adjacency[num_columns]) {
  }
  ~ColumnSubgraph() {
    delete[] adj_list_;
  }
  void AddEdge(Edge e) {
    int part = e.left.partition;
    assert(part < num_columns_);

    adj_list_[part][e.left].push_back(e.right);
  }
  void GetColumn(int part, vector<Edge>* out) const {
    const Adjacency& a = adj_list_[part];
    for (auto& kv : a) {
      for (auto& right : kv.second) {
        Edge e;
        e.left = kv.first;
        e.right = right;
        out->push_back(e);
      }
    }
  }
  // Get the nodes in the next partition adjacent to node N
  void GetAdjacentNodes(Node n, vector<Node>* out) const {
    int part = n.partition;
    const Adjacency& a = adj_list_[part];

    // log("GetAdjacentNodes %s, part %d", n.ToString().c_str(), part);

    auto it = a.find(n);
    if (it == a.end()) {
      return;
    }
    // TODO: it would be better not to copy these.
    for (auto node : it->second) {
      out->push_back(node);
    }
  }

  // accessor
  int num_columns() const { return num_columns_; }

  // for debugging only
  string ToString() const {
    string s("[\n");
    char buf[100];
    for (int i = 0; i < num_columns_; ++i) {
      const Adjacency& a = adj_list_[i];
      snprintf(buf, sizeof(buf), "%d (%zu) ", i, a.size());
      s += string(buf);
      s += AdjacencyToString(a);
      s += "\n";
    }
    s += " ]";
    return s;
  }

 private:
  int num_columns_;
  // Adjacency list.  An array of k-1 maps.
  // Lookup goes from nodes in partition i to nodes in partition i+1.
  Adjacency* adj_list_;
};

void BuildColumnSubgraph(const Graph& g, ColumnSubgraph* a) {
  for (const auto& e : g.edges) {
    if (e.left.partition + 1 == e.right.partition) {
      a->AddEdge(e);
    }
  }
}

// A 2D array of paths.  It's an array because all paths are the same length.
// We use a single vector<> to represent it, to reduce memory allocation.
class PathArray {
 public:
  explicit PathArray(int path_length)
     : path_length_(path_length),
       num_paths_(0) {
  }
  void AddEdgeAsPath(Edge e) {
    // Can only initialize PathArray with edges when path length is 2
    assert(path_length_ == 2);

    nodes_.push_back(e.left);
    nodes_.push_back(e.right);
    num_paths_++;
  }
  Node LastNodeInPath(int index) const {
    int start = index * path_length_;
    return nodes_[start + path_length_ -1];
  }
  // Pretty print a single path in this array.  For debugging only.
  string PathDebugString(int index) const {
    string s("[ ");
    for (int i = index * path_length_; i < (index + 1) * path_length_; ++i) {
      s += nodes_[i].ToString();
      s += " - ";
    }
    s += " ]";
    return s;
  }
  // Print the word implied by the path.
  string PathAsString(int index) const {
    string s;
    for (int i = index * path_length_; i < (index + 1) * path_length_; ++i) {
      s += nodes_[i].ngram[0];
      s += nodes_[i].ngram[1];
    }
    return s;
  }
  const Node* GetPathStart(int index) const {
    return &nodes_[index * path_length_];
  }
  void AddPath(const Node* start, int prefix_length, Node right) {
    // Make sure it is one less
    assert(prefix_length == path_length_-1);

    // TODO: replace with memcpy?  Is it faster?
    for (int i = 0; i < prefix_length; ++i) {
      nodes_.push_back(start[i]);
    }
    nodes_.push_back(right);
    num_paths_++;
  }

  // accessors
  int num_paths() const { return num_paths_; }
  int path_length() const { return path_length_; }

 private:
  int path_length_;
  int num_paths_;
  vector<Node> nodes_;
};

// Given a PathArray of length i, produce one of length i+1.
//
// NOTE: It would be more efficient to filter 'right_nodes' here, and only add
// a new path if it forms a "partial clique" (at step i+1).  This amounts to
// doing the membership tests in edge_set for each "column", instead of waiting
// until the end.
//
// This will reduce the exponential blowup of EnumeratePaths (although it
// doesn't change the worst case).

void EnumerateStep(
    const ColumnSubgraph& subgraph, const PathArray& in, PathArray* out) {

  int prefix_length = in.path_length();

  for (int i = 0; i < in.num_paths(); ++i) {
    // log("col %d, path %d", col, i);

    // last node in every path
    Node last_node = in.LastNodeInPath(i);

    // TODO: avoid copying of nodes?
    vector<Node> right_nodes;
    subgraph.GetAdjacentNodes(last_node, &right_nodes);

    // Get a pointer to the start of the path
    const Node* start = in.GetPathStart(i);

    for (Node right : right_nodes) {
      out->AddPath(start, prefix_length, right);
    }
  }
}

// Given a the column subgraph, produce an array of all possible paths of
// length k.  These will be subsequently checked to see if they are cliques.
void EnumeratePaths(
    const ColumnSubgraph& subgraph, PathArray* candidates) {
  // edges between partitions 0 and 1, a "column" of edges
  vector<Edge> edges0;
  subgraph.GetColumn(0, &edges0);

  int num_columns = subgraph.num_columns();
  PathArray** arrays = new PathArray*[num_columns];

  // Initialize using column 0.
  int path_length = 2;
  arrays[0] = new PathArray(path_length);
  for (auto& e : edges0) {
    arrays[0]->AddEdgeAsPath(e);
  }

  // Iterate over columns 1 to k-1.
  for (int i = 1; i < num_columns; ++i) {
    log("--- Column %d", i);

    path_length++;
    if (i == num_columns - 1) {
      arrays[i] = candidates;  // final result, from output argument!
    } else {
      arrays[i] = new PathArray(path_length);  // intermediate result
    }
    PathArray* in = arrays[i - 1];
    PathArray* out = arrays[i];

    EnumerateStep(subgraph, *in, out);

    log("in num paths: %d", in->num_paths());
    log("out num paths: %d", out->num_paths());

    // We create an destroy a PathArray on every iteration.  On each
    // iteration, the PathArray grows both rows and columns, so it's hard to
    // avoid this.
    delete in;
  }
}

// Inserts the path number 'p' in incomplete if the path is not a complete
// subgraph.
bool IsClique(const Node* path, int k, const EdgeSet& edge_set) {
  // We need to ensure that (k choose 2) edges are all in edge_set.
  // We already know that k-1 of them are present, so we need to check (k
  // choose 2) - (k-1).
  for (int i = 0; i < k; ++i) {
    for (int j = i + 1; j < k; ++j) {
      if (i + 1 == j) {
        // Already know this edge exists.  NOTE: does this even speed things
        // up?  It's a branch in the middle of an inner loop.
        continue;
      }
      Edge e;
      e.left = path[i];
      e.right = path[j];
      if (edge_set.find(e) == edge_set.end()) {
        log("Didn't find edge %s", e.ToString().c_str());
        return false;
      }
    }
  }
  return true;
}

void CheckForCliques(const PathArray& candidates,
                     const EdgeSet& edge_set,
                     unordered_set<int>* incomplete) {
  int k = candidates.path_length();
  for (int p = 0; p < candidates.num_paths(); ++p) {
    const Node* path = candidates.GetPathStart(p);
    // NOTE: We could run many IsClique invocations in parallel.  It reads from
    // edge_set.  The different 'incomplete' sets can be merged.
    if (!IsClique(path, k, edge_set)) {
      incomplete->insert(p);
      return;  // IMPORTANT: early return
    }
  }
}

// Parse text on stdin into a graph, and do some validation.
bool ParseGraph(Graph* g, EdgeSet* edge_set) {
  // NOTE: It's possible that there NO k-cliques.

  int ret = fscanf(stdin, "num_partitions %d\n", &(g->num_partitions));
  if (ret != 1) {
    log("ERROR: Expected 'num_partitions <integer>'\n");
    return false;
  }
  log("num_partitions = %d", g->num_partitions);

  int ngram_size;
  ret = fscanf(stdin, "ngram_size %d\n", &ngram_size);
  if (ret != 1) {
    log("ERROR: Expected 'ngram_size <integer>'\n");
    return false;
  }
  if (ngram_size != 2) {
    log("ERROR: Only bigrams are currently supported (got n = %d)\n", ngram_size);
    return false;
  }

  int num_edges = 0;
  while (true) {
    int part1, part2;
    char c1, c2, c3, c4;
    int ret = fscanf(stdin, "edge %d.%c%c %d.%c%c\n",
                     &part1, &c1, &c2, &part2, &c3, &c4);
    if (ret == EOF) {
      log("Read %d edges", num_edges);
      break;
    }
    if (ret != 6) {
      log("ERROR: Expected 6 values for edge, got %d", ret);
      return false;
    }
    // log("%d -> %d", part1, part2);
    if (part1 >= part2) {
      log("ERROR: edge in wrong order (%d >= %d)", part1, part2);
      return false;
    }

    Edge e;
    e.left.partition = part1;
    e.left.ngram[0] = c1;
    e.left.ngram[1] = c2;

    e.right.partition = part2;
    e.right.ngram[0] = c3;
    e.right.ngram[1] = c4;

    g->edges.push_back(e);

    // For lookup in CheckForCliques
    edge_set->insert(e);

    num_edges++;
  }
  return true;
}

int main() {
  log("sizeof(Node) = %zu", sizeof(Node));
  log("sizeof(Edge) = %zu", sizeof(Edge));
  // This should be true no matter what platform we use, e.g. since we use
  // uint16_t.
  assert(sizeof(Node) == 4);
  assert(sizeof(Edge) == 8);

  Graph g;
  EdgeSet edge_set;

  log("ParseGraph");
  if (!ParseGraph(&g, &edge_set)) {
    log("Fatal error parsing graph.");
    return 1;
  }

  // If there are k partitions, there are k-1 edge "columns".
  ColumnSubgraph subgraph(g.num_partitions - 1);
  log("BuildColumnSubgraph");
  BuildColumnSubgraph(g, &subgraph);
  log("%s", subgraph.ToString().c_str());

  // PathArray candidates(num_partitions);
  log("EnumeratePaths");
  PathArray candidates(g.num_partitions);
  EnumeratePaths(subgraph, &candidates);

  log("EnumeratePaths produced %d candidates", candidates.num_paths());
  for (int i = 0; i < candidates.num_paths(); ++i) {
    log("%d %s", i, candidates.PathDebugString(i).c_str());
  }

  // array of indices of incomplete paths, i.e. paths that are not complete
  // subgraphs
  log("CheckForCliques");
  unordered_set<int> incomplete;
  CheckForCliques(candidates, edge_set, &incomplete);
  for (auto p : incomplete) {
    log("Path %d is incomplete", p);
  }

  log("Found the following cliques/words:");
  // Now print all the complete ones to stdout
  for (int i = 0; i < candidates.num_paths(); i++) {
    if (incomplete.find(i) == incomplete.end()) {
      log("%d %s", i, candidates.PathAsString(i).c_str());
    }
  }
  log("Done");
}
