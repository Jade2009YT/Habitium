//
//  FetchUpcomingEventsUseCase.swift
//  Habitium
//
//  Domain-layer accessor for the "next N events/tasks" shown on HomeView
//  and mirrored into the calendar widget snapshot.
//

import Foundation

@MainActor
struct FetchUpcomingEventsUseCase {
    let repository: PlannerRepository

    func execute(limit: Int = 3) -> [UpcomingPlannerItem] {
        repository.upcomingItems(limit: limit)
    }
}
