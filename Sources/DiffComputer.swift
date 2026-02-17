import Foundation

enum DiffComputer {

    static func computeDiff(old: String, new: String) -> [DiffLine] {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let diff = newLines.difference(from: oldLines)

        // Build ordered operations
        var removes: [Int: String] = [:]  // oldOffset -> content
        var inserts: [Int: String] = [:]  // newOffset -> content

        for change in diff {
            switch change {
            case .remove(let offset, let element, _):
                removes[offset] = element
            case .insert(let offset, let element, _):
                inserts[offset] = element
            }
        }

        // Walk through both sequences to produce DiffLines
        var result: [DiffLine] = []
        var oldIdx = 0
        var newIdx = 0
        var oldLineNum = 1
        var newLineNum = 1

        while oldIdx < oldLines.count || newIdx < newLines.count {
            let isRemoved = removes[oldIdx] != nil
            let isInserted = inserts[newIdx] != nil

            if isRemoved && isInserted {
                // Modified line — compute inline changes
                let oldContent = oldLines[oldIdx]
                let newContent = newLines[newIdx]
                let (removeInline, insertInline) = computeInlineChanges(old: oldContent, new: newContent)

                result.append(DiffLine(
                    type: .removed,
                    content: oldContent,
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil,
                    inlineChanges: removeInline
                ))
                result.append(DiffLine(
                    type: .added,
                    content: newContent,
                    oldLineNumber: nil,
                    newLineNumber: newLineNum,
                    inlineChanges: insertInline
                ))
                oldIdx += 1
                newIdx += 1
                oldLineNum += 1
                newLineNum += 1
            } else if isRemoved {
                result.append(DiffLine(
                    type: .removed,
                    content: oldLines[oldIdx],
                    oldLineNumber: oldLineNum,
                    newLineNumber: nil,
                    inlineChanges: []
                ))
                oldIdx += 1
                oldLineNum += 1
            } else if isInserted {
                result.append(DiffLine(
                    type: .added,
                    content: newLines[newIdx],
                    oldLineNumber: nil,
                    newLineNumber: newLineNum,
                    inlineChanges: []
                ))
                newIdx += 1
                newLineNum += 1
            } else {
                // Unchanged
                if oldIdx < oldLines.count {
                    result.append(DiffLine(
                        type: .unchanged,
                        content: oldLines[oldIdx],
                        oldLineNumber: oldLineNum,
                        newLineNumber: newLineNum,
                        inlineChanges: []
                    ))
                }
                oldIdx += 1
                newIdx += 1
                oldLineNum += 1
                newLineNum += 1
            }
        }

        return result
    }

    // MARK: - Inline character-level diff

    private static func computeInlineChanges(old: String, new: String) -> ([InlineChange], [InlineChange]) {
        let oldChars = Array(old)
        let newChars = Array(new)

        let charDiff = newChars.difference(from: oldChars)

        var removedIndices = IndexSet()
        var insertedIndices = IndexSet()

        for change in charDiff {
            switch change {
            case .remove(let offset, _, _):
                removedIndices.insert(offset)
            case .insert(let offset, _, _):
                insertedIndices.insert(offset)
            }
        }

        let removeRanges = contiguousRanges(from: removedIndices).map {
            InlineChange(range: NSRange(location: $0.lowerBound, length: $0.count), isAddition: false)
        }
        let insertRanges = contiguousRanges(from: insertedIndices).map {
            InlineChange(range: NSRange(location: $0.lowerBound, length: $0.count), isAddition: true)
        }

        return (removeRanges, insertRanges)
    }

    private static func contiguousRanges(from indexSet: IndexSet) -> [Range<Int>] {
        indexSet.rangeView.map { $0 }
    }
}
