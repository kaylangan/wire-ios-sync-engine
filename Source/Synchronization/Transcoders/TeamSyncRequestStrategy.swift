//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//


public final class TeamSyncRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource, ZMRequestGeneratorSource {

    public struct SyncConfiguration {
        let basePath: String
        let pageSize: UInt
        let startKey: String
        let remoteIdSyncSize: UInt

        static let `default` = SyncConfiguration(
            basePath: TeamDownloadRequestFactory.teamPath,
            pageSize: 50,
            startKey: "start",
            remoteIdSyncSize: 1
        )
    }

    fileprivate let syncConfiguration: SyncConfiguration

    fileprivate weak var syncStatus: SyncStatus?

    /// The sync used to fetch the teams and their metadata.
    /// The team ids will be stored in the memberSync to download.
    fileprivate var teamListSync: ZMSimpleListRequestPaginator!

    /// The sync used to fetch a teams members.
    fileprivate var memberSync: ZMRemoteIdentifierObjectSync!

    public init(
        withManagedObjectContext managedObjectContext: NSManagedObjectContext,
        applicationStatus: ApplicationStatus,
        syncStatus: SyncStatus,
        syncConfiguration: SyncConfiguration) {

        self.syncConfiguration = syncConfiguration
        self.syncStatus = syncStatus
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = .allowsRequestsDuringSync
        memberSync = ZMRemoteIdentifierObjectSync(transcoder: self, managedObjectContext: managedObjectContext)

        teamListSync = ZMSimpleListRequestPaginator(
            basePath: syncConfiguration.basePath,
            startKey: syncConfiguration.startKey,
            pageSize: syncConfiguration.pageSize,
            managedObjectContext: managedObjectContext,
            includeClientID: false,
            transcoder: self
        )
    }

    public convenience init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus, syncStatus: SyncStatus) {
        self.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus, syncStatus: syncStatus, syncConfiguration: .default)
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        if isSyncing && teamListSync.status != .inProgress && memberSync.isDone {
            markExistingTeamsAsNeedingToBeDownloaded()
            teamListSync.resetFetching()
            memberSync.setRemoteIdentifiersAsNeedingDownload([])
        }
        return requestGenerators.nextRequest()
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return []
    }

    public var requestGenerators: [ZMRequestGenerator] {
        return [teamListSync, memberSync]
    }

    fileprivate func finishSyncIfCompleted() {
        guard isSyncing, memberSync.isDone, !teamListSync.hasMoreToFetch else { return }
        syncStatus?.finishCurrentSyncPhase()
    }

    fileprivate var isSyncing: Bool {
        return syncStatus?.currentSyncPhase == .fetchingTeams
    }

    private func markExistingTeamsAsNeedingToBeDownloaded() {
        // It can happen that the user is offline for longer than 4 weeks,
        // in this case said user will miss events and we will perform a slow sync.
        // In the case the user got removed from a team that the user already has locally in that period,
        // we want to ensure that we delete that team from the client. The `/teams` request will only
        // return the teams the user is still in of course, so we fetch all local teams and mark them
        // as `needsToBeUpdatedFromBackend`, we reset this flag for all teams we fetch during the slow sync,
        // (we just fetched them so there is no need to do it again after the slow sync completed).
        // After the slow sync we will try to fetch the deleted teams and receive a 4xx response and delete the team locally.
        let request = Team.sortedFetchRequest()
        guard let existingTeams = managedObjectContext.executeFetchRequestOrAssert(request) as? [Team] else { return }
        existingTeams.forEach {
            $0.needsToBeUpdatedFromBackend = true
        }
    }
    
}


// MARK: - ZMSimpleListRequestPaginatorSync


extension TeamSyncRequestStrategy: ZMSimpleListRequestPaginatorSync {

    public func nextUUID(from response: ZMTransportResponse!, forListPaginator paginator: ZMSimpleListRequestPaginator!) -> UUID! {
        let payload = response.payload?.asDictionary() as? [String: Any]
        let teamsPayload = payload?["teams"] as? [[String: Any]]

        let teams = teamsPayload?.flatMap { (payload) -> Team? in
            guard let id = (payload["id"] as? String).flatMap(UUID.init) else { return nil }
            let team = Team.fetchOrCreate(with: id, create: true, in: managedObjectContext, created: nil)
            team?.update(with: payload)
            // See `markExistingTeamsAsNeedingToBeDownloaded`
            team?.needsToBeUpdatedFromBackend = false
            return team
        }

        teams?.forEach {
            memberSync.addRemoteIdentifiersThatNeedDownload([$0.remoteIdentifier!])
        }

        if response.result == .permanentError && isSyncing {
            syncStatus?.failCurrentSyncPhase()
        }

        finishSyncIfCompleted()
        return teams?.last?.remoteIdentifier
    }

    public func shouldParseError(for response: ZMTransportResponse!) -> Bool {
        // Otherwise `nextUUID(from:forListPaginator:)` won't be called
        // and we won't fail the current sync phase.
        return true
    }

}


// MARK: - ZMRemoteIdentifierObjectTranscoder


extension TeamSyncRequestStrategy: ZMRemoteIdentifierObjectTranscoder {

    public func maximumRemoteIdentifiersPerRequest(for sync: ZMRemoteIdentifierObjectSync!) -> UInt {
        return syncConfiguration.remoteIdSyncSize
    }

    public func request(for sync: ZMRemoteIdentifierObjectSync!, remoteIdentifiers identifiers: Set<UUID>!) -> ZMTransportRequest! {
        return identifiers.first.map(TeamDownloadRequestFactory.getMembersRequest)
    }

    public func didReceive(_ response: ZMTransportResponse!, remoteIdentifierObjectSync sync: ZMRemoteIdentifierObjectSync!, forRemoteIdentifiers remoteIdentifiers: Set<UUID>!) {

        if let identifier = remoteIdentifiers.first {
            let payload = response.payload?.asDictionary() as? [String: Any]
            let membersPayload = payload?["members"] as? [[String: Any]]

            membersPayload?.forEach { payload in
                if let team = Team.fetchOrCreate(with: identifier, create: true, in: managedObjectContext, created: nil) {
                    Member.createOrUpdate(with: payload, in: team, context: managedObjectContext)
                }
            }
        }

        if response.result == .permanentError && isSyncing {
            syncStatus?.failCurrentSyncPhase()
        }

        finishSyncIfCompleted()
    }

}