import BestASRMCPCore

// Thin entry — everything testable lives in BestASRMCPCore.
let server = BestASRMCPServer()
try await server.run()
