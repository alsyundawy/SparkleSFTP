import Foundation

/// Pure Swift 6 IP Subnet and CIDR calculation engine ported from SubnetCalc for macOS.
public enum IPSubnetCalculator {
    public enum SubnetError: Error, LocalizedError, Equatable {
        case invalidIPv4Address(String)
        case invalidCIDRPrefix(Int)
        case invalidNetmask(String)

        public var errorDescription: String? {
            switch self {
            case .invalidIPv4Address(let text):
                return "Invalid IPv4 address format: '\(text)'"
            case .invalidCIDRPrefix(let prefix):
                return "Invalid CIDR prefix /\(prefix); must be between 0 and 32."
            case .invalidNetmask(let mask):
                return "Invalid subnet mask: '\(mask)'"
            }
        }
    }

    public struct CalculationResult: Sendable, Equatable {
        public let ipAddress: String
        public let cidrPrefix: Int
        public let netmask: String
        public let wildcardMask: String
        public let networkAddress: String
        public let broadcastAddress: String
        public let firstUsableHost: String
        public let lastUsableHost: String
        public let totalHosts: UInt64
        public let usableHosts: UInt64
        public let ipClass: String
        public let scope: String
        public let binaryIP: String
        public let hexIP: String

        public init(
            ipAddress: String,
            cidrPrefix: Int,
            netmask: String,
            wildcardMask: String,
            networkAddress: String,
            broadcastAddress: String,
            firstUsableHost: String,
            lastUsableHost: String,
            totalHosts: UInt64,
            usableHosts: UInt64,
            ipClass: String,
            scope: String,
            binaryIP: String,
            hexIP: String
        ) {
            self.ipAddress = ipAddress
            self.cidrPrefix = cidrPrefix
            self.netmask = netmask
            self.wildcardMask = wildcardMask
            self.networkAddress = networkAddress
            self.broadcastAddress = broadcastAddress
            self.firstUsableHost = firstUsableHost
            self.lastUsableHost = lastUsableHost
            self.totalHosts = totalHosts
            self.usableHosts = usableHosts
            self.ipClass = ipClass
            self.scope = scope
            self.binaryIP = binaryIP
            self.hexIP = hexIP
        }
    }

    /// Calculates comprehensive subnet details for an IPv4 CIDR string (e.g. "192.168.1.100/24").
    public static func calculate(cidrText: String) throws -> CalculationResult {
        let trimmed = cidrText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1])
        else {
            throw SubnetError.invalidIPv4Address(cidrText)
        }
        return try calculate(address: String(parts[0]), prefix: prefix)
    }

    /// Calculates comprehensive subnet details for an IPv4 address and prefix.
    public static func calculate(address: String, prefix: Int) throws -> CalculationResult {
        guard prefix >= 0 && prefix <= 32 else {
            throw SubnetError.invalidCIDRPrefix(prefix)
        }
        guard let ipInt = parseIPv4(address) else {
            throw SubnetError.invalidIPv4Address(address)
        }

        let maskInt: UInt32 = prefix == 0 ? 0 : (~0 << (32 - prefix))
        let wildcardInt = ~maskInt
        let netInt = ipInt & maskInt
        let bcastInt = ipInt | wildcardInt

        let totalHosts: UInt64 = prefix == 32 ? 1 : (1 << UInt64(32 - prefix))
        let usableHosts: UInt64
        let firstHostStr: String
        let lastHostStr: String

        if prefix == 32 {
            usableHosts = 1
            firstHostStr = formatIPv4(ipInt)
            lastHostStr = formatIPv4(ipInt)
        } else if prefix == 31 {
            usableHosts = 2 // RFC 3021 point-to-point links
            firstHostStr = formatIPv4(netInt)
            lastHostStr = formatIPv4(bcastInt)
        } else {
            usableHosts = totalHosts > 2 ? totalHosts - 2 : 0
            firstHostStr = formatIPv4(netInt + 1)
            lastHostStr = formatIPv4(bcastInt - 1)
        }

        return CalculationResult(
            ipAddress: address,
            cidrPrefix: prefix,
            netmask: formatIPv4(maskInt),
            wildcardMask: formatIPv4(wildcardInt),
            networkAddress: formatIPv4(netInt),
            broadcastAddress: formatIPv4(bcastInt),
            firstUsableHost: firstHostStr,
            lastUsableHost: lastHostStr,
            totalHosts: totalHosts,
            usableHosts: usableHosts,
            ipClass: classifyClass(ipInt),
            scope: classifyScope(ipInt),
            binaryIP: formatBinary(ipInt),
            hexIP: String(format: "0x%08X", ipInt)
        )
    }

    /// Converts dotted decimal netmask to CIDR prefix (e.g. "255.255.255.0" -> 24).
    public static func netmaskToPrefix(_ maskString: String) -> Int? {
        guard let maskInt = parseIPv4(maskString) else { return nil }
        var temp = maskInt
        var count = 0
        while temp & 0x8000_0000 != 0 {
            count += 1
            temp <<= 1
        }
        guard temp == 0 else { return nil } // Non-contiguous mask
        return count
    }

    private static func parseIPv4(_ text: String) -> UInt32? {
        let octets = text.split(separator: ".")
        guard octets.count == 4 else { return nil }
        var result: UInt32 = 0
        for octet in octets {
            guard let val = UInt32(octet), val <= 255 else { return nil }
            result = (result << 8) | val
        }
        return result
    }

    private static func formatIPv4(_ val: UInt32) -> String {
        let octet1 = (val >> 24) & 0xFF
        let octet2 = (val >> 16) & 0xFF
        let octet3 = (val >> 8) & 0xFF
        let octet4 = val & 0xFF
        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }

    private static func formatBinary(_ val: UInt32) -> String {
        let octets = [
            (val >> 24) & 0xFF,
            (val >> 16) & 0xFF,
            (val >> 8) & 0xFF,
            val & 0xFF
        ]
        return octets.map { octet in
            let bin = String(octet, radix: 2)
            return String(repeating: "0", count: max(0, 8 - bin.count)) + bin
        }.joined(separator: ".")
    }

    private static func classifyClass(_ val: UInt32) -> String {
        let first = (val >> 24) & 0xFF
        switch first {
        case 0...127: return "Class A"
        case 128...191: return "Class B"
        case 192...223: return "Class C"
        case 224...239: return "Class D (Multicast)"
        default: return "Class E (Experimental)"
        }
    }

    private static func classifyScope(_ val: UInt32) -> String {
        let first = (val >> 24) & 0xFF
        let second = (val >> 16) & 0xFF
        if first == 10 { return "Private (RFC 1918)" }
        if first == 172 && (16...31).contains(second) { return "Private (RFC 1918)" }
        if first == 192 && second == 168 { return "Private (RFC 1918)" }
        if first == 127 { return "Loopback" }
        if first == 169 && second == 254 { return "Link-Local (RFC 3927)" }
        if (224...239).contains(first) { return "Multicast" }
        return "Public Internet"
    }
}
