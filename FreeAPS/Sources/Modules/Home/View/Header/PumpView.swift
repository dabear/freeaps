import SwiftUI

struct PumpView: View {
    @Binding var reservoir: Decimal?
    @Binding var battery: Battery?
    @Binding var name: String
    @Binding var expiresAtDate: Date?
    @Binding var timerDate: Date

    private var reservoirFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var batteryFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        return formatter
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reservoir = reservoir {
                HStack {
                    Image(systemName: "drop.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 8)
                        .foregroundColor(reservoirColor)
                    if reservoir == 0xDEAD_BEEF {
                        Text("50+ U").font(.system(size: 12, weight: .bold))
                    } else {
                        Text(
                            reservoirFormatter
                                .string(from: reservoir as NSNumber)! + NSLocalizedString(" U", comment: "Insulin unit")
                        )
                        .font(.system(size: 12, weight: .bold))
                    }
                }
            }
            if let battery = battery, battery.display ?? false, expiresAtDate == nil {
                HStack {
                    Image(systemName: "battery.100")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 8)
                        .foregroundColor(batteryColor)
                    Text("\(Int(battery.percent ?? 100)) %").font(.system(size: 12, weight: .bold))
                }
            }

            if let date = expiresAtDate {
                HStack {
                    Image(systemName: "stopwatch.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 8)
                        .foregroundColor(timerColor)
                    Text(remainingTimeString(time: date.timeIntervalSince(timerDate))).font(.system(size: 12, weight: .bold))
                }
            }
        }
    }

    private func remainingTimeString(time: TimeInterval) -> String {
        guard time > 0 else {
            return "Replace pod"
        }

        var time = time
        let days = Int(time / 1.days.timeInterval)
        time -= days.days.timeInterval
        let hours = Int(time / 1.hours.timeInterval)
        time -= hours.hours.timeInterval
        let minutes = Int(time / 1.minutes.timeInterval)

        if days >= 1 {
<<<<<<< HEAD
            return "\(days)d \(hours)h"
=======
            return "\(days)" + NSLocalizedString("d", comment: "abbreviation for days") + " \(hours)" +
                NSLocalizedString("h", comment: "abbreviation for hours")
>>>>>>> 2c29d12 (iOS 15 broken menu fixed)
        }

        if hours >= 1 {
            return "\(hours)h"
        }

        return "\(minutes)m"
    }

    private var batteryColor: Color {
        guard let battery = battery, let percent = battery.percent else {
            return .gray
        }

        switch percent {
        case ...10:
            return .loopRed
        case ...20:
            return .loopYellow
        default:
            return .loopGreen
        }
    }

    private var reservoirColor: Color {
        guard let reservoir = reservoir else {
            return .gray
        }

        switch reservoir {
        case ...10:
            return .loopRed
        case ...30:
            return .loopYellow
        default:
            return .insulin
        }
    }

    private var timerColor: Color {
        guard let expisesAt = expiresAtDate else {
            return .gray
        }

        let time = expisesAt.timeIntervalSince(timerDate)

        switch time {
        case ...8.hours.timeInterval:
            return .loopRed
        case ...1.days.timeInterval:
            return .loopYellow
        default:
            return .loopGreen
        }
    }
}
