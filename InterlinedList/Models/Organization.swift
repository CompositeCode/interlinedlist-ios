//
//  Organization.swift
//  InterlinedList
//

import Foundation

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let isPublic: Bool?
}
