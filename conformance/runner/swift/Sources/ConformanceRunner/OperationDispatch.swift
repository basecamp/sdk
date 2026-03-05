import Foundation
import Basecamp

/// Result of executing an SDK operation.
struct OpResult {
    var error: (any Error)?
    var meta: [String: Any]?
}

/// Dispatches to the appropriate SDK service method based on operation name.
func executeOperation(_ tc: TestCase, account: AccountClient) async -> OpResult {
    do {
        switch tc.operation {
        case "ListProjects":
            let result = try await account.projects.list()
            return OpResult(meta: ["totalCount": result.meta.totalCount])

        case "GetProject":
            let projectId = intParam(tc.pathParams, "projectId")
            _ = try await account.projects.get(projectId: projectId)
            return OpResult()

        case "CreateProject":
            let name = stringParam(tc.requestBody, "name", fallback: "Conformance Test")
            _ = try await account.projects.create(req: CreateProjectRequest(name: name))
            return OpResult()

        case "UpdateProject":
            let projectId = intParam(tc.pathParams, "projectId")
            let name = stringParam(tc.requestBody, "name", fallback: "Conformance Test")
            _ = try await account.projects.update(projectId: projectId, req: UpdateProjectRequest(name: name))
            return OpResult()

        case "TrashProject":
            let projectId = intParam(tc.pathParams, "projectId")
            try await account.projects.trash(projectId: projectId)
            return OpResult()

        case "ListTodos":
            let todolistId = intParam(tc.pathParams, "todolistId")
            let result = try await account.todos.list(todolistId: todolistId)
            return OpResult(meta: ["totalCount": result.meta.totalCount])

        case "GetTodo":
            let todoId = intParam(tc.pathParams, "todoId")
            _ = try await account.todos.get(todoId: todoId)
            return OpResult()

        case "CreateTodo":
            let todolistId = intParam(tc.pathParams, "todolistId")
            let content = stringParam(tc.requestBody, "content", fallback: "Conformance Test")
            _ = try await account.todos.create(todolistId: todolistId, req: CreateTodoRequest(content: content))
            return OpResult()

        case "GetTimesheetEntry":
            let entryId = intParam(tc.pathParams, "entryId")
            _ = try await account.timesheets.get(entryId: entryId)
            return OpResult()

        case "UpdateTimesheetEntry":
            let entryId = intParam(tc.pathParams, "entryId")
            var req = UpdateTimesheetEntryRequest()
            if let date = tc.requestBody?["date"]?.stringValue { req.date = date }
            if let hours = tc.requestBody?["hours"]?.stringValue { req.hours = hours }
            if let desc = tc.requestBody?["description"]?.stringValue { req.description = desc }
            _ = try await account.timesheets.update(entryId: entryId, req: req)
            return OpResult()

        case "GetProjectTimeline":
            let projectId = intParam(tc.pathParams, "projectId")
            _ = try await account.timeline.projectTimeline(projectId: projectId)
            return OpResult()

        case "GetProgressReport":
            _ = try await account.reports.progress()
            return OpResult()

        case "GetPersonProgress":
            let personId = intParam(tc.pathParams, "personId")
            _ = try await account.reports.personProgress(personId: personId)
            return OpResult()

        case "GetProjectTimesheet":
            let projectId = intParam(tc.pathParams, "projectId")
            _ = try await account.timesheets.forProject(projectId: projectId)
            return OpResult()

        case "ListWebhooks":
            let bucketId = intParam(tc.pathParams, "bucketId")
            _ = try await account.webhooks.list(bucketId: bucketId)
            return OpResult()

        case "CreateWebhook":
            let bucketId = intParam(tc.pathParams, "bucketId")
            let payloadUrl = stringParam(tc.requestBody, "payload_url", fallback: "")
            var types: [String] = []
            if let arr = tc.requestBody?["types"]?.arrayValue {
                types = arr.compactMap(\.stringValue)
            }
            _ = try await account.webhooks.create(
                bucketId: bucketId,
                req: CreateWebhookRequest(payloadUrl: payloadUrl, types: types)
            )
            return OpResult()

        default:
            return OpResult(error: RunnerError.unknownOperation(tc.operation))
        }
    } catch {
        return OpResult(error: error)
    }
}

// MARK: - Param Helpers

private func intParam(_ params: [String: JSONValue]?, _ key: String) -> Int {
    params?[key]?.intValue ?? 0
}

private func stringParam(_ params: [String: JSONValue]?, _ key: String, fallback: String) -> String {
    let value = params?[key]?.stringValue
    return (value?.isEmpty == false) ? value! : fallback
}

/// Internal runner errors.
enum RunnerError: Error {
    case unknownOperation(String)
}
