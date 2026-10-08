
import Combine
import Foundation

@MainActor
final class EnvironmentManager: ObservableObject {
    static let shared = EnvironmentManager()

    @Published private(set) var environments: [DNSEnvironment] = []

    private var userDefaultsKey: String {
        UITestConfiguration.storageKey("dnsdeck.environments")
    }

    private init() {
        loadEnvironments()
    }

    func loadEnvironments() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([DNSEnvironment].self, from: data)
        else {
            if environments.isEmpty {
                createDefaultEnvironment()
            }
            return
        }
        environments = decoded.sorted {
            if $0.isStarred != $1.isStarred {
                return $0.isStarred && !$1.isStarred
            }
            return $0.createdAt < $1.createdAt
        }
    }

    func saveEnvironments() {
        guard let encoded = try? JSONEncoder().encode(environments) else { return }
        UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
    }

    func createEnvironment(name: String) -> DNSEnvironment {
        let environment = DNSEnvironment(name: name)
        environments.append(environment)
        saveEnvironments()
        return environment
    }

    func updateEnvironment(_ environment: DNSEnvironment) {
        guard let index = environments.firstIndex(where: { $0.id == environment.id }) else { return }
        environments[index] = environment
        saveEnvironments()
    }

    func deleteEnvironment(_ environment: DNSEnvironment) {
        environments.removeAll { $0.id == environment.id }
        saveEnvironments()
    }

    func environment(withId id: UUID) -> DNSEnvironment? {
        environments.first { $0.id == id }
    }

    func toggleStar(for environment: DNSEnvironment) {
        guard let index = environments.firstIndex(where: { $0.id == environment.id }) else { return }
        var updated = environment
        updated.isStarred.toggle()
        environments[index] = updated
        saveEnvironments()
    }

    private func createDefaultEnvironment() {
        let defaultEnv = UITestConfiguration.isEnabled ?
            DNSEnvironment(id: UITestConfiguration.environmentID, name: UITestConfiguration.environmentName) :
            DNSEnvironment(name: "Default")
        environments.append(defaultEnv)
        saveEnvironments()
    }
}
