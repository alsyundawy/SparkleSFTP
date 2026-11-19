import AppKit
import SparkleCore
import SparkleDesignSystem
import SwiftUI

/// Native IPv4 CIDR and Subnet Calculator sheet (ported from SubnetCalc for macOS).
public struct SubnetCalculatorSheet: View {
    @ObservedObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var inputCIDR: String = "192.168.1.1/24"
    @State private var result: IPSubnetCalculator.CalculationResult?
    @State private var errorMessage: String?
    @State private var copiedField: String?

    public init(appState: AppState, initialCIDR: String = "192.168.1.1/24") {
        self.appState = appState
        self._inputCIDR = State(initialValue: initialCIDR)
    }

    private var palette: SparkleThemePalette {
        appState.activePalette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SparkleTheme.Spacing.medium) {
            headerView
            inputSectionView
            if let result {
                resultsDetailsView(result)
            } else if let errorMessage {
                errorNoticeView(errorMessage)
            }
            Spacer(minLength: 0)
            footerActionView
        }
        .padding(SparkleTheme.Spacing.large)
        .frame(width: 620, height: 480)
        .sparkleWorkspaceSurface(palette)
        .onAppear {
            performCalculation()
        }
    }

    private var headerView: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(palette.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("IPv4 Subnet & CIDR Calculator")
                    .font(.headline)
                    .foregroundStyle(palette.primaryTextColor)
                Text("Subnet calculation engine ported from SubnetCalc for macOS")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryTextColor)
            }
            Spacer()
        }
    }

    private var inputSectionView: some View {
        HStack(spacing: SparkleTheme.Spacing.small) {
            TextField("Enter IP/CIDR (e.g. 10.0.0.1/24)", text: $inputCIDR)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .onSubmit {
                    performCalculation()
                }

            Button("Calculate") {
                performCalculation()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    private func resultsDetailsView(_ res: IPSubnetCalculator.CalculationResult) -> some View {
        VStack(spacing: 8) {
            Group {
                resultRow(title: "Network Address", value: "\(res.networkAddress)/\(res.cidrPrefix)")
                resultRow(title: "Subnet Netmask", value: res.netmask)
                resultRow(title: "Wildcard Mask", value: res.wildcardMask)
                resultRow(title: "Usable Host Range", value: "\(res.firstUsableHost) – \(res.lastUsableHost)")
                resultRow(title: "Broadcast Address", value: res.broadcastAddress)
            }
            Divider()
            Group {
                resultRow(title: "Usable Hosts", value: "\(res.usableHosts) (Total: \(res.totalHosts))")
                resultRow(title: "IP Class & Scope", value: "\(res.ipClass) · \(res.scope)")
                resultRow(title: "Binary Address", value: res.binaryIP)
                resultRow(title: "Hexadecimal IP", value: res.hexIP)
            }
        }
        .padding(SparkleTheme.Spacing.small)
        .background(palette.canvasColor.opacity(0.4))
        .cornerRadius(6)
    }

    private func resultRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(palette.secondaryTextColor)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(palette.primaryTextColor)
            Spacer()
            Button(action: {
                copyToClipboard(value: value, name: title)
            }, label: {
                Image(systemName: copiedField == title ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copiedField == title ? palette.accentColor : palette.secondaryTextColor)
            })
            .buttonStyle(.plain)
            .help("Copy \(title)")
        }
    }

    @ViewBuilder
    private func errorNoticeView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(palette.primaryTextColor)
        }
        .padding(SparkleTheme.Spacing.small)
    }

    private var footerActionView: some View {
        HStack {
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func performCalculation() {
        do {
            result = try IPSubnetCalculator.calculate(cidrText: inputCIDR)
            errorMessage = nil
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }

    private func copyToClipboard(value: String, name: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        copiedField = name
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedField == name {
                copiedField = nil
            }
        }
    }
}
