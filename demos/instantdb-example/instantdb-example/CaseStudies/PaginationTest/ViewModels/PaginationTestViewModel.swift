import Foundation
import InstantDB

@MainActor
class PaginationTestViewModel: ObservableObject {
  @Published var goals: [Goal] = []
  @Published var isLoading = false
  @Published var error: String?
  @Published var logs: [String] = []

  @Published var hasNextPage = false
  @Published var hasPreviousPage = false
  @Published var currentPage = 1
  @Published var pageSize = 5
  @Published var sortOrder: SortDirection = .asc

  private var startCursor: Cursor?
  private var endCursor: Cursor?
  private var subscriptions = Set<SubscriptionToken>()
  private weak var db: InstantClient?

  func setup(db: InstantClient) {
    self.db = db
    loadFirstPage()
  }

  func loadFirstPage() {
    guard let db = db else { return }

    subscriptions.removeAll()
    currentPage = 1
    startCursor = nil
    endCursor = nil

    log("[INFO] Loading first page (size: \(pageSize), order: \(sortOrder.rawValue))")

    do {
      try db.subscribe(
        db.query(Goal.self)
          .order(by: "title", sortOrder)
          .first(pageSize)
      ) { [weak self] result in
        guard let self else { return }
        self.handleResult(result, isFirstPage: true)
      }
      .store(in: &subscriptions)
    } catch {
      log("[ERROR] Failed to load first page: \(error.localizedDescription)")
    }
  }

  func loadNextPage() {
    guard let db = db, let cursor = endCursor else {
      log("[WARN] No end cursor available for next page")
      return
    }

    subscriptions.removeAll()
    currentPage += 1

    log("[INFO] Loading next page (page: \(currentPage))")

    do {
      try db.subscribe(
        db.query(Goal.self)
          .order(by: "title", sortOrder)
          .first(pageSize)
          .after(cursor)
      ) { [weak self] result in
        guard let self else { return }
        self.handleResult(result, isFirstPage: false)
      }
      .store(in: &subscriptions)
    } catch {
      log("[ERROR] Failed to load next page: \(error.localizedDescription)")
    }
  }

  func loadPreviousPage() {
    guard let db = db, let cursor = startCursor else {
      log("[WARN] No start cursor available for previous page")
      return
    }

    subscriptions.removeAll()
    currentPage = max(1, currentPage - 1)

    log("[INFO] Loading previous page (page: \(currentPage))")

    do {
      try db.subscribe(
        db.query(Goal.self)
          .order(by: "title", sortOrder)
          .last(pageSize)
          .before(cursor)
      ) { [weak self] result in
        guard let self else { return }
        self.handleResult(result, isFirstPage: false)
      }
      .store(in: &subscriptions)
    } catch {
      log("[ERROR] Failed to load previous page: \(error.localizedDescription)")
    }
  }

  func toggleSortOrder() {
    sortOrder = sortOrder == .asc ? .desc : .asc
    log("[INFO] Sort order changed to: \(sortOrder.rawValue)")
    loadFirstPage()
  }

  func changePageSize(_ newSize: Int) {
    pageSize = newSize
    log("[INFO] Page size changed to: \(newSize)")
    loadFirstPage()
  }

  func createSampleGoals() {
    guard let db = db else { return }

    let sampleTitles = [
      "Alpha Goal", "Beta Goal", "Charlie Goal", "Delta Goal", "Echo Goal",
      "Foxtrot Goal", "Golf Goal", "Hotel Goal", "India Goal", "Juliet Goal",
      "Kilo Goal", "Lima Goal", "Mike Goal"
    ]

    log("[INFO] Creating \(sampleTitles.count) sample goals...")

    do {
      try db.transact {
        for (index, title) in sampleTitles.enumerated() {
          Goal.create(
            title: title,
            difficulty: (index % 5) + 1,
            completed: index % 2 == 0
          )
        }
      }
      log("[SUCCESS] Created \(sampleTitles.count) sample goals")
    } catch {
      log("[ERROR] Failed to create sample goals: \(error.localizedDescription)")
    }
  }

  func deleteAllGoals() {
    guard let db = db else { return }

    log("[INFO] Deleting all \(goals.count) goals...")

    do {
      try db.transact {
        for goal in goals {
          Goal.delete(id: goal.id)
        }
      }
      log("[SUCCESS] Deleted all goals")
    } catch {
      log("[ERROR] Failed to delete goals: \(error.localizedDescription)")
    }
  }

  private func handleResult(_ result: TypedResult<Goal>, isFirstPage: Bool) {
    isLoading = result.isLoading
    error = result.error?.localizedDescription
    goals = result.data

    if let pageInfo = result.pageInfo {
      startCursor = pageInfo.startCursor
      endCursor = pageInfo.endCursor
      hasNextPage = pageInfo.hasNextPage
      hasPreviousPage = pageInfo.hasPreviousPage

      if !result.isLoading {
        log("[INFO] Received \(result.data.count) goals | hasNext: \(pageInfo.hasNextPage) | hasPrev: \(pageInfo.hasPreviousPage)")
      }
    } else {
      if !result.isLoading {
        log("[WARN] No pageInfo in result - pagination may not be working")
      }
    }
  }

  private func log(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    logs.insert("[\(timestamp)] \(message)", at: 0)
    if logs.count > 50 {
      logs.removeLast()
    }
  }
}
