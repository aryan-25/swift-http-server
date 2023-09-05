import HTTPTypes
import NIOPosix

@main
struct Example {
    static func main() async throws {
        let server = HTTPServer(responder: EchoResponder(), eventLoopGroup: MultiThreadedEventLoopGroup.singleton)

        try await server.run()
    }
}

struct EchoResponder: HTTPResponder {
    func respond(request: HTTPRequest, body: RequestBody, responseHeaderWriter: consuming ResponseHeaderWriter) async throws {
        print("Handling request \(request)")
        let writer = try await responseHeaderWriter.writeResponseHead(.init(status: .ok))

        for try await chunk in body {
            print("Received body chunk \(String(buffer: chunk))")
            try await writer.writeBodyChunk(chunk)
        }

        print("Writing response end")
        try await writer.writeEnd(nil)
    }
}
