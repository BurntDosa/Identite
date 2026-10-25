import Foundation

let specimen = ["P<UTOERIKSSON<<ANNA<MARIA<<<<<<<<<<<<<<<<<<<", "L898902C36UTO7408122F1204159ZE184226B<<<<<10"]

let cal: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return calendar
}()
let id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}
