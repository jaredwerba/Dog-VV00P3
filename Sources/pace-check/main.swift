import Darwin
import VV00PCore

let failures = VV00PChecks.failures()
if failures.isEmpty {
    print("pace-check passed")
} else {
    for failure in failures {
        print("FAIL \(failure)")
    }
    exit(1)
}
