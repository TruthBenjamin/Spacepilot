import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../../../storage/domain/models/scanned_file.dart';
import '../../domain/models/models.dart';

final class SimilarImageDetectorService {
  const SimilarImageDetectorService({this.hashOverrides = const {}});

  final Map<String, int> hashOverrides;

  Future<List<SimilarImageGroup>> findSimilarImagesInScannedFiles(
    Iterable<ScannedFile> files, {
    int minSizeBytes = 0,
    int maxHammingDistance = 8,
  }) async {
    final candidates = files
        .where((file) => file.size >= minSizeBytes && _isSupportedImage(file))
        .map(_candidateForScannedFile)
        .toList(growable: false);

    return _findSimilarGroups(
      candidates,
      maxHammingDistance: maxHammingDistance,
    );
  }

  Future<List<SimilarImageGroup>> findSimilarImages(
    Iterable<File> files, {
    int minSizeBytes = 0,
    int maxHammingDistance = 8,
  }) async {
    final candidates = <_ImageCandidate>[];

    for (final file in files) {
      final candidate = await _candidateFor(file);
      if (candidate == null || candidate.sizeBytes < minSizeBytes) continue;
      candidates.add(candidate);
    }

    return _findSimilarGroups(
      candidates,
      maxHammingDistance: maxHammingDistance,
    );
  }

  Future<List<SimilarImageGroup>> _findSimilarGroups(
    List<_ImageCandidate> candidates, {
    required int maxHammingDistance,
  }) async {
    final hashed = <_HashedImageCandidate>[];

    for (final candidate in candidates) {
      final hash =
          hashOverrides[candidate.path] ?? await _perceptualHash(candidate);
      if (hash == null) continue;
      hashed.add(_HashedImageCandidate(candidate: candidate, hash: hash));
    }

    if (hashed.length < 2) return const [];

    final parent = List<int>.generate(hashed.length, (index) => index);
    final pairScores = <_ImagePairScore>[];

    for (var i = 0; i < hashed.length - 1; i++) {
      for (var j = i + 1; j < hashed.length; j++) {
        final distance = _hammingDistance(hashed[i].hash, hashed[j].hash);
        if (distance > maxHammingDistance) continue;

        _union(parent, i, j);
        pairScores.add(
          _ImagePairScore(
            first: i,
            second: j,
            score: _similarityScore(distance),
          ),
        );
      }
    }

    final indexesByRoot = <int, List<int>>{};
    for (var i = 0; i < hashed.length; i++) {
      indexesByRoot.putIfAbsent(_find(parent, i), () => <int>[]).add(i);
    }

    final groups = <SimilarImageGroup>[];
    for (final indexes in indexesByRoot.values) {
      if (indexes.length < 2) continue;

      final indexSet = indexes.toSet();
      final scores = pairScores
          .where(
            (pair) =>
                indexSet.contains(pair.first) && indexSet.contains(pair.second),
          )
          .map((pair) => pair.score)
          .toList(growable: false);
      if (scores.isEmpty) continue;

      final files =
          indexes
              .map((index) => hashed[index])
              .map(
                (image) => SimilarImageFile(
                  name: image.candidate.name,
                  path: image.candidate.path,
                  sizeBytes: image.candidate.sizeBytes,
                  lastModified: image.candidate.lastModified,
                  perceptualHash: image.hash.toRadixString(16).padLeft(16, '0'),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => b.sizeBytes.compareTo(a.sizeBytes));

      groups.add(
        SimilarImageGroup(
          files: files,
          averageSimilarityScore:
              scores.reduce((a, b) => a + b) / scores.length,
          strongestSimilarityScore: scores.reduce(math.max),
        ),
      );
    }

    groups.sort((a, b) {
      final bytes = b.recoverableBytes.compareTo(a.recoverableBytes);
      if (bytes != 0) return bytes;
      return b.strongestSimilarityScore.compareTo(a.strongestSimilarityScore);
    });

    return groups;
  }

  Future<int?> _perceptualHash(_ImageCandidate candidate) async {
    try {
      final bytes = await File(candidate.path).readAsBytes();
      return perceptualHashFromBytes(bytes);
    } on FileSystemException {
      return null;
    } on Exception {
      return null;
    }
  }

  static Future<int?> perceptualHashFromBytes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.Codec? codec;
    ui.FrameInfo? frame;

    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      codec = await descriptor.instantiateCodec(
        targetWidth: 9,
        targetHeight: 8,
      );
      frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      );
      if (byteData == null) return null;
      return perceptualHashFromRgba(byteData.buffer.asUint8List(), 9, 8);
    } on Exception {
      return null;
    } finally {
      frame?.image.dispose();
      codec?.dispose();
      buffer?.dispose();
    }
  }

  static int perceptualHashFromRgba(Uint8List rgba, int width, int height) {
    if (width < 9 || height < 8 || rgba.length < width * height * 4) {
      throw ArgumentError('A 9x8 RGBA image is required for dHash.');
    }

    var hash = 0;
    var bit = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final left = _lumaAt(rgba, width, x, y);
        final right = _lumaAt(rgba, width, x + 1, y);
        if (left > right) {
          hash |= 1 << bit;
        }
        bit++;
      }
    }

    return hash;
  }

  static int hammingDistance(int firstHash, int secondHash) {
    return _hammingDistance(firstHash, secondHash);
  }

  static double similarityScore(int hammingDistance) {
    return _similarityScore(hammingDistance);
  }

  Future<_ImageCandidate?> _candidateFor(File file) async {
    try {
      final path = file.absolute.path;
      if (!_isSupportedImagePath(path)) return null;

      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) return null;

      return _ImageCandidate(
        name: p.basename(path),
        path: path,
        sizeBytes: stat.size,
        lastModified: stat.modified,
      );
    } on FileSystemException {
      return null;
    }
  }

  _ImageCandidate _candidateForScannedFile(ScannedFile file) {
    return _ImageCandidate(
      name: file.filename,
      path: file.path,
      sizeBytes: file.size,
      lastModified: file.lastModified,
    );
  }

  static int _hammingDistance(int firstHash, int secondHash) {
    var value = firstHash ^ secondHash;
    var distance = 0;
    while (value != 0) {
      value &= value - 1;
      distance++;
    }
    return distance;
  }

  static double _similarityScore(int hammingDistance) {
    return ((64 - hammingDistance.clamp(0, 64)) / 64 * 100).clamp(0, 100);
  }

  static double _lumaAt(Uint8List rgba, int width, int x, int y) {
    final offset = (y * width + x) * 4;
    return rgba[offset] * 0.299 +
        rgba[offset + 1] * 0.587 +
        rgba[offset + 2] * 0.114;
  }

  static int _find(List<int> parent, int index) {
    if (parent[index] != index) {
      parent[index] = _find(parent, parent[index]);
    }
    return parent[index];
  }

  static void _union(List<int> parent, int first, int second) {
    final firstRoot = _find(parent, first);
    final secondRoot = _find(parent, second);
    if (firstRoot != secondRoot) {
      parent[secondRoot] = firstRoot;
    }
  }

  bool _isSupportedImage(ScannedFile file) {
    return _isSupportedImagePath(file.filename) ||
        _isSupportedImagePath(file.path);
  }

  static bool _isSupportedImagePath(String path) {
    final extension = p.extension(path).replaceFirst('.', '').toLowerCase();
    return _imageExtensions.contains(extension);
  }
}

final class _HashedImageCandidate {
  const _HashedImageCandidate({required this.candidate, required this.hash});

  final _ImageCandidate candidate;
  final int hash;
}

final class _ImageCandidate {
  const _ImageCandidate({
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.lastModified,
  });

  final String name;
  final String path;
  final int sizeBytes;
  final DateTime lastModified;
}

final class _ImagePairScore {
  const _ImagePairScore({
    required this.first,
    required this.second,
    required this.score,
  });

  final int first;
  final int second;
  final double score;
}

const Set<String> _imageExtensions = {'jpeg', 'jpg', 'png', 'webp'};
