import Foundation

@main struct NavigationTests {
    static func main() throws {
        let path = CommandLine.arguments[1]
        guard let nav = WorldNavigation.load(path) else { fatalError("route failed validation") }
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
        let samples = try JSONDecoder().decode([[Double]].self, from: data)
        for s in samples {
            let at = nav.move(x:s[0],z:s[1],dx:s[2],dz:s[3])
            precondition(abs(at.x-s[4]) < 1e-8 && abs(at.z-s[5]) < 1e-8)
            precondition(nav.allows(at.x,at.z))
            precondition(abs(nav.ground(at.x,at.z)!-s[6]) < 1e-8)
        }
        // Invalid data must not enter the movement loop or index a malformed row.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath:path))) as! [String:Any]
        for mutation in [["areas":[[1,2]]], ["spawn":[0,0,0,0]], ["version":2], ["eye_height":-1]] as [[String:Any]] {
            var broken = json
            for (key,value) in mutation { broken[key] = value }
            let bytes = try JSONSerialization.data(withJSONObject:broken)
            let bad = try JSONDecoder().decode(WorldNavigation.self,from:bytes)
            precondition(!bad.valid)
        }
        json["areas"] = []
        let bytes = try JSONSerialization.data(withJSONObject:json)
        let empty = try JSONDecoder().decode(WorldNavigation.self,from:bytes)
        precondition(!empty.valid)
        print("Swift/Python navigation parity: \(samples.count) swept movements and surface heights passed; malformed routes rejected")
    }
}
