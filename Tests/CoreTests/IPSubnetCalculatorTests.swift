import Foundation
import SparkleCore
import Testing

@Suite("IP Subnet & CIDR Calculator Tests")
struct IPSubnetCalculatorTests {
    @Test("IPSubnetCalculator calculates standard /24 IPv4 subnet correctly")
    func standardClassCSubnet() throws {
        let res = try IPSubnetCalculator.calculate(cidrText: "192.168.1.50/24")
        #expect(res.ipAddress == "192.168.1.50")
        #expect(res.cidrPrefix == 24)
        #expect(res.netmask == "255.255.255.0")
        #expect(res.wildcardMask == "0.0.0.255")
        #expect(res.networkAddress == "192.168.1.0")
        #expect(res.broadcastAddress == "192.168.1.255")
        #expect(res.firstUsableHost == "192.168.1.1")
        #expect(res.lastUsableHost == "192.168.1.254")
        #expect(res.totalHosts == 256)
        #expect(res.usableHosts == 254)
        #expect(res.ipClass == "Class C")
        #expect(res.scope == "Private (RFC 1918)")
        #expect(res.hexIP == "0xC0A80132")
    }

    @Test("IPSubnetCalculator calculates /30 point-to-point subnet")
    func pointToPointSubnet() throws {
        let res = try IPSubnetCalculator.calculate(address: "10.0.0.1", prefix: 30)
        #expect(res.netmask == "255.255.255.252")
        #expect(res.totalHosts == 4)
        #expect(res.usableHosts == 2)
        #expect(res.networkAddress == "10.0.0.0")
        #expect(res.firstUsableHost == "10.0.0.1")
        #expect(res.lastUsableHost == "10.0.0.2")
        #expect(res.broadcastAddress == "10.0.0.3")
    }

    @Test("IPSubnetCalculator calculates /32 single host")
    func singleHostSubnet() throws {
        let res = try IPSubnetCalculator.calculate(address: "8.8.8.8", prefix: 32)
        #expect(res.netmask == "255.255.255.255")
        #expect(res.totalHosts == 1)
        #expect(res.usableHosts == 1)
        #expect(res.networkAddress == "8.8.8.8")
        #expect(res.broadcastAddress == "8.8.8.8")
        #expect(res.scope == "Public Internet")
    }

    @Test("IPSubnetCalculator detects invalid IP addresses and prefixes")
    func invalidInputs() {
        #expect(throws: IPSubnetCalculator.SubnetError.self) {
            _ = try IPSubnetCalculator.calculate(cidrText: "256.1.1.1/24")
        }
        #expect(throws: IPSubnetCalculator.SubnetError.self) {
            _ = try IPSubnetCalculator.calculate(address: "192.168.1.1", prefix: 33)
        }
    }

    @Test("IPSubnetCalculator converts dotted decimal netmask to prefix")
    func testNetmaskToPrefix() {
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.255.0") == 24)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.0.0") == 16)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.0.0.0") == 8)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.255.252") == 30)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.255.255") == 32)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.255.128") == 25)
        #expect(IPSubnetCalculator.netmaskToPrefix("255.255.255.1") == nil) // non-contiguous
    }
}
