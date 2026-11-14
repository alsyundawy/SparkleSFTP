import Foundation
import SparkleCore

extension ConfigImporter {
    /// Evaluates duplicate connections against existing repository and prepares an actionable plan.
    public static func buildImportPlan(
        bundle: SparkleConfigBundle,
        existingProfiles: [ConnectionProfile],
        existingGroups: [ServerGroup]
    ) -> ConfigImportPlan {
        let isIntegrityValid = ConfigBundleCrypto.verifyIntegrity(bundle: bundle)
        var existingKeyMap: [String: ConnectionProfile] = [:]
        for profile in existingProfiles {
            let key = profileKey(profile)
            existingKeyMap[key] = profile
        }

        var newProfiles: [ConnectionProfile] = []
        var conflictingProfiles: [(existing: ConnectionProfile, imported: ConnectionProfile)] = []

        for imported in bundle.payload.profiles {
            let key = profileKey(imported)
            if let existing = existingKeyMap[key] {
                conflictingProfiles.append((existing: existing, imported: imported))
            } else {
                newProfiles.append(imported)
            }
        }

        let existingGroupNames = Set(existingGroups.map { $0.name.lowercased() })
        let newGroups = bundle.payload.groups.filter { !existingGroupNames.contains($0.name.lowercased()) }

        return ConfigImportPlan(
            bundle: bundle,
            sourceFormat: detectFormat(data: Data(), filename: bundle.kind),
            newProfiles: newProfiles,
            conflictingProfiles: conflictingProfiles,
            newGroups: newGroups,
            newBookmarks: bundle.payload.bookmarks,
            newSnippets: bundle.payload.snippets,
            integrityVerified: isIntegrityValid
        )
    }

    private static func profileKey(_ profile: ConnectionProfile) -> String {
        "\(profile.protocolType.rawValue):\(profile.host.lowercased()):\(profile.port):\(profile.username.lowercased())"
    }

    /// Applies import plan into `ConnectionStore`, executing the chosen conflict resolution policy.
    public static func applyPlan(
        plan: ConfigImportPlan,
        policy: ConfigImportConflictPolicy,
        connectionStore: ConnectionStore
    ) async throws -> ConfigImportResult {
        var result = ConfigImportResult()
        await commitGroups(plan.newGroups, into: connectionStore, result: &result)
        await commitNewProfiles(plan.newProfiles, into: connectionStore, result: &result)
        for (existing, imported) in plan.conflictingProfiles {
            await resolveConflict(
                existing: existing,
                imported: imported,
                policy: policy,
                into: connectionStore,
                result: &result
            )
        }
        return result
    }

    private static func commitGroups(
        _ groups: [ServerGroup],
        into store: ConnectionStore,
        result: inout ConfigImportResult
    ) async {
        for group in groups {
            do {
                try await store.saveGroup(group)
                result.importedGroupCount += 1
            } catch {
                result.warnings.append("Could not create group '\(group.name)': \(error.localizedDescription)")
            }
        }
    }

    private static func commitNewProfiles(
        _ profiles: [ConnectionProfile],
        into store: ConnectionStore,
        result: inout ConfigImportResult
    ) async {
        for profile in profiles {
            do {
                try await store.saveProfile(profile)
                result.importedProfileCount += 1
            } catch {
                result.warnings.append("Failed to import '\(profile.name)': \(error.localizedDescription)")
            }
        }
    }

    private static func resolveConflict(
        existing: ConnectionProfile,
        imported: ConnectionProfile,
        policy: ConfigImportConflictPolicy,
        into store: ConnectionStore,
        result: inout ConfigImportResult
    ) async {
        switch policy {
        case .skipExisting:
            result.skippedProfileCount += 1

        case .overwrite:
            let updated = imported.copying(id: existing.id)
            do {
                try await store.saveProfile(updated)
                result.updatedProfileCount += 1
            } catch {
                result.warnings.append("Failed to overwrite '\(existing.name)': \(error.localizedDescription)")
            }

        case .keepBoth:
            let renamed = imported.copying(id: UUID(), name: "\(imported.name) (Imported)")
            do {
                try await store.saveProfile(renamed)
                result.importedProfileCount += 1
            } catch {
                result.warnings.append("Failed to import copy '\(renamed.name)': \(error.localizedDescription)")
            }

        case .mergeGroups:
            let targetGroupID = imported.groupID ?? existing.groupID
            let merged = imported.copying(id: existing.id, groupID: .some(targetGroupID))
            do {
                try await store.saveProfile(merged)
                result.updatedProfileCount += 1
            } catch {
                result.warnings.append("Failed to merge '\(existing.name)': \(error.localizedDescription)")
            }
        }
    }
}
