let server = EchoServer(host: "127.0.0.1", port: 8060)
do {
    try server.start()
} catch let error {
    print("Error: \(error.localizedDescription)")
    server.stop()
}
