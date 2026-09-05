import Foundation

/// Sunrise / sunset from latitude and longitude, computed locally.
///
/// Uses the standard low-precision solar position model (mean anomaly → equation of centre →
/// ecliptic longitude → declination → hour angle). Accurate to about a minute at temperate
/// latitudes, which is well inside what a screen filter needs, and it avoids both a network
/// call and the Location Services permission prompt.
enum Solar {
    private static let rad = Double.pi / 180
    private static let obliquity = rad * 23.4397
    private static let j1970 = 2440588.0
    private static let j2000 = 2451545.0
    private static let leadingEdge = 0.0009
    /// Standard refraction-corrected solar altitude for sunrise/sunset.
    private static let horizon = -0.833 * (Double.pi / 180)

    private static func toDays(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86400 - 0.5 + j1970 - j2000
    }

    private static func fromJulian(_ j: Double) -> Date {
        Date(timeIntervalSince1970: (j + 0.5 - j1970) * 86400)
    }

    private static func meanAnomaly(_ days: Double) -> Double {
        rad * (357.5291 + 0.98560028 * days)
    }

    private static func eclipticLongitude(_ m: Double) -> Double {
        let center = rad * (1.9148 * sin(m) + 0.02 * sin(2 * m) + 0.0003 * sin(3 * m))
        let perihelion = rad * 102.9372
        return m + center + perihelion + .pi
    }

    private static func declination(_ eclipticLongitude: Double) -> Double {
        asin(sin(obliquity) * sin(eclipticLongitude))
    }

    /// Returns the sunrise and sunset bracketing the solar noon nearest `date`.
    /// Returns nil above the Arctic / below the Antarctic circle when the sun neither
    /// rises nor sets that day.
    static func events(date: Date, latitude: Double, longitude: Double) -> (
        sunrise: Date, sunset: Date
    )? {
        let lw = rad * -longitude
        let phi = rad * latitude
        let days = toDays(date)

        let cycle = (days - leadingEdge - lw / (2 * .pi)).rounded()
        let approxTransit = leadingEdge + lw / (2 * .pi) + cycle
        let m = meanAnomaly(approxTransit)
        let l = eclipticLongitude(m)
        let dec = declination(l)
        let noon = j2000 + approxTransit + 0.0053 * sin(m) - 0.0069 * sin(2 * l)

        let cosHourAngle = (sin(horizon) - sin(phi) * sin(dec)) / (cos(phi) * cos(dec))
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        let hourAngle = acos(cosHourAngle)

        let setTransit = leadingEdge + (hourAngle + lw) / (2 * .pi) + cycle
        let jSet = j2000 + setTransit + 0.0053 * sin(m) - 0.0069 * sin(2 * l)
        let jRise = noon - (jSet - noon)

        return (fromJulian(jRise), fromJulian(jSet))
    }

    /// True when `date` falls between sunset and the following sunrise.
    /// Above the polar circles, falls back to "is the sun below the horizon at local noon".
    static func isNight(at date: Date, latitude: Double, longitude: Double) -> Bool {
        guard let today = events(date: date, latitude: latitude, longitude: longitude) else {
            // Polar day or polar night. Decide by declination against latitude.
            let dec = declination(eclipticLongitude(meanAnomaly(toDays(date))))
            return (latitude >= 0) ? (dec < 0) : (dec > 0)
        }
        if date >= today.sunset { return true }
        if date < today.sunrise { return true }
        return false
    }
}
