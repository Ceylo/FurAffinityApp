//
//  String.swift
//  FurAffinity
//
//  Created by Ceylo on 03/09/2024.
//

extension String {
    func containsAllOrderedCharacters(from pattern: String) -> Bool {
        guard !pattern.isEmpty else {
            return true
        }
        
        let parent = self.lowercased()
        let pattern = pattern.lowercased()
        var nextCharToMatchIt = pattern.startIndex
        
        for char in parent {
            let charToMatch = pattern[nextCharToMatchIt]
            if char == charToMatch {
                nextCharToMatchIt = pattern.index(after: nextCharToMatchIt)
            }
            
            if nextCharToMatchIt == pattern.endIndex {
                return true
            }
        }
        
        return false
    }
}
