import Foundation

/// Maps anonymous diarization speaker ids to enrolled names by comparing their
/// embeddings (spec diarization; #26 design D1).
///
/// Pure and self-owned on purpose: rather than trusting the vendored SDK's
/// known-speaker pre-load path (which, on the DiarizerManager pipeline, does not
/// feed enrolled voices into the clustering decision), identification is a
/// post-hoc cosine-distance match over the embeddings the run already produced.
/// Fully unit-testable without models or audio.
public enum SpeakerIdentifier {
    /// Cosine distance in [0, 2]: 0 = identical direction, 1 = orthogonal.
    /// (1 - cosine similarity.) Zero-magnitude vectors are treated as maximally
    /// distant so they never spuriously match.
    public static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 2 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return 2 }
        return 1 - dot / (na.squareRoot() * nb.squareRoot())
    }

    /// For each raw speaker id, the enrolled name whose embedding is closest —
    /// but only when that closest distance is below `threshold`. Raw ids with no
    /// enrolled match (or below threshold) are omitted, so the caller keeps their
    /// `SPEAKER_N` ordinals. Ties resolve to the earlier name in sorted order for
    /// determinism. Default threshold mirrors the SDK's `speakerThreshold` (0.65).
    public static func resolve(
        embeddings: [String: [Float]],
        enrolled: [(name: String, embedding: [Float])],
        threshold: Float = 0.65
    ) -> [String: String] {
        guard !enrolled.isEmpty else { return [:] }
        var mapping: [String: String] = [:]
        for (rawId, embedding) in embeddings {
            var best: (name: String, distance: Float)?
            for e in enrolled.sorted(by: { $0.name < $1.name }) {
                let d = cosineDistance(embedding, e.embedding)
                if best == nil || d < best!.distance { best = (e.name, d) }
            }
            if let best, best.distance < threshold { mapping[rawId] = best.name }
        }
        return mapping
    }
}
