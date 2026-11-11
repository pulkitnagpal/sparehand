import AppKit
import Foundation

/// Realistic screenshots for the demo account: rendered text that on-device OCR can read, with macOS-style names and dates
/// spread over the last few months. Nothing here tells Sparehand what to do; it only makes a believable messy Desktop.
enum DemoSeed {
    static let screens: [(app: String, lines: [String])] = [
        ("Amazon", ["Order placed, thank you", "Order #408-3381926 · Arriving Thursday", "Logitech MX Master 3S mouse", "Order total ₹8,995.00"]),
        ("Uber", ["Your Tuesday evening trip", "Total ₹486.20", "Koramangala to Indiranagar · 7.4 km", "Paid with UPI"]),
        ("Swiggy", ["Order delivered", "Paneer tikka bowl, Garlic naan x2", "Bill total ₹612", "Delivered in 28 mins"]),
        ("IndiGo", ["Boarding pass", "6E 2134 · BLR → DEL", "Seat 14C · Gate 22", "Boarding 06:40"]),
        ("Booking.com", ["Booking confirmed", "Hotel Ibis Goa Calangute", "Check-in Fri 20 Dec · 2 nights", "Total ₹9,840"]),
        ("Airbnb", ["Your trip to Manali", "Cozy cabin with mountain view", "Dec 27 – Dec 30 · 3 guests", "Confirmation HMX2Q8"]),
        ("WhatsApp", ["Mom", "Did you book the tickets for Diwali?", "Yes, sending the PNR now", "Call me when you land"]),
        ("Messages", ["Rahul", "Dinner at Toit at 8?", "Sure, I'll book a table for four", "See you there"]),
        ("WhatsApp", ["Flat 4B group", "Water tanker coming at 7am tomorrow", "Please keep the gate open", "Maintenance due by the 5th"]),
        ("Recipe", ["Chocolate chip cookies", "2 cups flour, 1 cup butter, 1 cup brown sugar", "Bake at 180°C for 12 minutes", "Makes 24 cookies"]),
        ("Recipe", ["Masala chai", "2 cups water, 1 cup milk, 2 tsp tea", "Crushed ginger and cardamom", "Simmer 5 minutes"]),
        ("YouTube", ["How to make sourdough bread at home", "Joshua Weissman · 2.1M views", "Step 3: the stretch and fold"]),
        ("Dribbble", ["Finance app dashboard concept", "Clean cards, soft gradients", "Liked by 1,204 designers"]),
        ("Pinterest", ["Living room ideas", "Warm minimal Scandinavian living room", "Oak shelves, linen sofa, plants"]),
        ("Figma", ["Onboarding v3 · Frame 2", "Welcome back, Priya", "Continue with Apple", "Skip for now"]),
        ("Settings", ["Something went wrong", "Error 0x80070005: access denied", "Try again later or contact support"]),
        ("Netflix", ["Continue watching", "The Night Agent · S2 E4", "47 min left"]),
        ("Bank", ["Payment successful", "Electricity bill BESCOM", "Amount ₹2,130.00", "Ref no 4482910331"]),
        ("Airtel", ["Your bill for October", "Postpaid plan ₹799", "Due date 18 Nov"]),
        ("Calendar", ["Dentist appointment", "Saturday 10:30 AM", "Smile Dental Clinic, HSR Layout"]),
        ("Maps", ["Third Wave Coffee", "4.5 ★ · Cafe · Open until 11 PM", "12 min walk"]),
        ("Twitter", ["@naval", "Seek wealth, not money or status.", "48K likes"]),
        ("Instagram", ["Goa sunset from the beach shack", "Liked by priya and 213 others"]),
        ("Gmail", ["Your Zomato order receipt", "Order total ₹740", "Thanks for ordering"]),
        ("Flipkart", ["Order confirmed", "boAt Airdopes 141", "Total ₹1,299", "Delivery by Sunday"]),
    ]

    static func run(home: URL, count: Int) {
        let desk = home.appendingPathComponent("Desktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: desk, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd 'at' h.mm.ss"
        let ampm = DateFormatter(); ampm.dateFormat = "a"
        var made = 0
        for i in 0..<count {
            let s = screens[i % screens.count]
            let date = Date().addingTimeInterval(-Double(i) * 86_400 * 3.7 - Double(i * 1931 % 7200))
            let name = "Screenshot \(f.string(from: date))\u{202F}\(ampm.string(from: date)).png"
            let url = desk.appendingPathComponent(name)
            guard let png = render(s.app, s.lines) else { continue }
            try? png.write(to: url)
            try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
            made += 1
        }
        print("put \(made) screenshots on \(desk.path)")
    }

    static func render(_ app: String, _ lines: [String]) -> Data? {
        let size = NSSize(width: 1200, height: 760)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.97, alpha: 1).setFill(); NSRect(origin: .zero, size: size).fill()
        NSColor(white: 0.9, alpha: 1).setFill(); NSRect(x: 0, y: size.height - 64, width: size.width, height: 64).fill()
        let head: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: NSColor.darkGray]
        (app as NSString).draw(at: NSPoint(x: 40, y: size.height - 46), withAttributes: head)
        var y = size.height - 150
        for (i, l) in lines.enumerated() {
            let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: i == 0 ? 40 : 30, weight: i == 0 ? .bold : .regular), .foregroundColor: NSColor.black]
            (l as NSString).draw(at: NSPoint(x: 60, y: y), withAttributes: a)
            y -= i == 0 ? 80 : 60
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
