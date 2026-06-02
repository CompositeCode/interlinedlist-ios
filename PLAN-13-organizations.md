# Plan 13 — Organizations

## Status
All endpoints are marked "Needs Bearer" in the API docs. Test each with the existing Bearer token before assuming they are blocked. If 401s are returned, the server work must be done first.

## Goal
Add a full Organizations section: model types, API methods, a list view, and a detail view with member management.

## Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/organizations` | List user's orgs |
| POST | `/api/organizations` | Create org |
| GET | `/api/organizations/[id]` | Org detail |
| PATCH | `/api/organizations/[id]` | Update org |
| DELETE | `/api/organizations/[id]` | Delete org |
| GET | `/api/organizations/[id]/members` | List members |
| POST | `/api/organizations/[id]/members` | Add member |
| DELETE | `/api/organizations/[id]/members/[userId]` | Remove member |

## Files to Create / Change

| File | Action |
|------|--------|
| `InterlinedList/Models/Organization.swift` | **Create** |
| `InterlinedList/Services/APIClient.swift` | Add org methods |
| `InterlinedList/Views/OrganizationsView.swift` | **Create** |
| `InterlinedList/Views/MainTabView.swift` | Add Organizations tab |
| `InterlinedList.xcodeproj/project.pbxproj` | Add new files |

## Step-by-Step

### 1. `Models/Organization.swift` — new file

```swift
import Foundation

struct Organization: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let slug: String?
    let createdAt: String?
    let updatedAt: String?
}

struct OrganizationMember: Identifiable, Codable {
    let id: String
    let username: String
    let displayName: String?
    let avatar: String?
    let role: String?
}

private struct OrgsResponse: Decodable { let organizations: [Organization] }
private struct OrgResponse: Decodable { let organization: Organization }
private struct MembersResponse: Decodable { let members: [OrganizationMember] }
```

Move the `OrgsResponse`/`OrgResponse`/`MembersResponse` wrappers inside `APIClient.swift` as private local structs, or leave them in the model file and make them `internal` — pick one consistently (use internal in model file so they aren't re-defined in APIClient).

### 2. `APIClient.swift` — add MARK: Organizations section

```swift
// MARK: - Organizations

func organizations() async throws -> [Organization] {
    struct R: Decodable { let organizations: [Organization] }
    return (try await get("/api/organizations") as R).organizations
}

func createOrganization(name: String, description: String?) async throws -> Organization {
    struct Body: Encodable { let name: String; let description: String? }
    struct R: Decodable { let organization: Organization? }
    let r: R = try await post("/api/organizations", body: Body(name: name, description: description))
    guard let org = r.organization else { throw APIError.noData }
    return org
}

func deleteOrganization(id: String) async throws {
    let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
    guard let url = URL(string: baseURL + "/api/organizations/\(enc)") else { throw APIError.invalidURL }
    var req = URLRequest(url: url)
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token = bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await session.data(for: req)
    try checkResponse(data: data, response: response)
}

func orgMembers(orgId: String) async throws -> [OrganizationMember] {
    let enc = orgId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orgId
    struct R: Decodable { let members: [OrganizationMember] }
    return (try await get("/api/organizations/\(enc)/members") as R).members
}

func addOrgMember(orgId: String, username: String) async throws {
    struct Body: Encodable { let username: String }
    struct R: Decodable { let ok: Bool? }
    let enc = orgId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orgId
    let _: R = try await post("/api/organizations/\(enc)/members", body: Body(username: username))
}

func removeOrgMember(orgId: String, userId: String) async throws {
    let encOrg = orgId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? orgId
    let encUser = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
    guard let url = URL(string: baseURL + "/api/organizations/\(encOrg)/members/\(encUser)") else { throw APIError.invalidURL }
    var req = URLRequest(url: url)
    req.httpMethod = "DELETE"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    if let token = bearerToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (data, response) = try await session.data(for: req)
    try checkResponse(data: data, response: response)
}
```

### 3. `Views/OrganizationsView.swift` — new file

Structure:
- `OrganizationsView` — top-level list with `@State var orgs: [Organization]`. Toolbar "+ New Org" button opens `CreateOrgSheet`. Swipe-to-delete calls `deleteOrganization`. `.task {}` loads orgs.
- `CreateOrgSheet` — `@State` form with name + description fields + Save button.
- `OrgDetailView` — shows org name, description, and a `MembersSection`. Toolbar "+ Add Member" opens `AddMemberSheet`.
- `MembersSection` — list of `OrganizationMember` rows with swipe-to-remove.
- `AddMemberSheet` — single `TextField("Username")` + Add button.

Keep each as a `private struct` inside the file except `OrganizationsView` which is `public`/`internal` (matches project convention of one `public struct` per file).

### 4. `MainTabView.swift` — add tab

Add an Organizations tab between Lists and Documents (or after Profile — pick the position that feels natural for the app's IA). Use SF Symbol `building.2` or `person.3`.

```swift
OrganizationsView()
    .tabItem { Label("Orgs", systemImage: "building.2") }
```

### 5. Xcode project — add new files

After creating the files, add them to the Xcode project target via:
- Drag into Xcode, OR
- Edit `project.pbxproj` to include references (the `swift-dev` agent handles this automatically when creating files via Write tool).

## Acceptance Criteria
- Organizations tab visible in `MainTabView`.
- Can create a new org; it appears in the list.
- Tapping an org opens `OrgDetailView` with its member list.
- Can add a member by username; member row appears.
- Can swipe-remove a member.
- Can swipe-delete an org from the list.
- 401 responses from any org endpoint trigger `authState.handleUnauthorized()`.
- Build succeeds.
