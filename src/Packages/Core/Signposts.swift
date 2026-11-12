import Foundation
import OSLog

public enum SparkleSignposts {
    public static let pointsOfInterest = OSSignposter(
        subsystem: "com.sparklesftp.SparkleSFTP",
        category: .pointsOfInterest
    )
    public static let launch = OSSignposter(
        subsystem: "com.sparklesftp.SparkleSFTP",
        category: "Launch"
    )
}
