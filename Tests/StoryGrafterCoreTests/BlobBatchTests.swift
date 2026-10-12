import Foundation
import Testing
@testable import StoryGrafterCore

@Suite struct BlobBatchTests {
    @Test func readsBlobsAndReportsMissingOnes() throws {
        let repo = try TempRepo()
        try repo.write("a.txt", "alpha\n")
        try repo.write("dir/b b.bin", Data([0, 10, 255, 10]))
        try repo.write("empty.txt", "")
        let sha = try repo.commit("one")
        let batch = try BlobBatch(git: repo.git)

        for _ in 0..<50 {
            #expect(try batch.blob(rev: sha, path: "a.txt") == Data("alpha\n".utf8))
            #expect(try batch.blob(rev: sha, path: "dir/b b.bin") == Data([0, 10, 255, 10]))
            #expect(try batch.blob(rev: sha, path: "empty.txt") == Data())
        }
        #expect(try batch.blob(rev: sha, path: "nope.txt") == nil)
        #expect(try batch.blob(rev: sha, path: "dir") == nil)
        #expect(try batch.blob(rev: sha, path: "a.txt") == Data("alpha\n".utf8))
    }
}
