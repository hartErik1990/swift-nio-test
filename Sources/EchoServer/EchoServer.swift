//
//  EchoServer.swift
//  CNIOAtomics
//
//  Created by Jonathan Wong on 4/25/18.
//

import Foundation
import NIO
import NIOSSL
import NIOHTTP2
import NIOHTTP1

enum EchoServerError: Error {
    case invalidHost
    case invalidPort
}

class EchoServer {
    private let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    private var host: String?
    var port: Int?
    
    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
    
    func start() throws {
        guard let host = host else {
            throw EchoServerError.invalidHost
        }
        guard let port = port else {
            throw EchoServerError.invalidPort
        }
        do {
            let channel = try serverBootstrap.bind(host: host, port: port).wait()
            print("Listening on \(String(describing: channel.localAddress))...")
            try channel.closeFuture.wait()
        } catch let error {
            throw error
        }
    }
    
    func stop() {
        do {
            try group.syncShutdownGracefully()
        } catch let error {
            print("Error shutting down \(error.localizedDescription)")
            exit(0)
        }
        print("Client connection closed")
    }
    private func makeSSLContext() -> NIOSSLContext {
        
        let key = try! NIOSSLPrivateKey(file: "/etc/letsencrypt/live/video-streams.me/fullchain.pem", format: .pem) { providePassword in
            providePassword("thisisagreatpassword".utf8)
        }
        let cert = try! NIOSSLCertificate(file: "/etc/letsencrypt/live/video-streams.me/privkey.pem", format: .pem)
        // Load the private key
        let sslPrivateKey = NIOSSLPrivateKeySource.privateKey(key)

        // Load the certificate
        let sslCertificate = NIOSSLCertificateSource.certificate(cert)

        // Set up the TLS configuration, it's important to set the `applicationProtocols` to
        // `NIOHTTP2SupportedALPNProtocols` which (using ALPN (https://en.wikipedia.org/wiki/Application-Layer_Protocol_Negotiation))
        // advertises the support of HTTP/2 to the client.
        var serverConfig = TLSConfiguration.makeServerConfiguration(certificateChain: [sslCertificate], privateKey: sslPrivateKey)
        serverConfig.applicationProtocols = NIOHTTP2SupportedALPNProtocols
        // Configure the SSL context that is used by all SSL handlers.
        let sslContext = try! NIOSSLContext(configuration: serverConfig)
        return sslContext
    }
    
    private var serverBootstrap: ServerBootstrap {
        let sslContext = makeSSLContext()
        return ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(BackPressureHandler()).flatMap {
                    //                    channel.pipeline.addHandler(EchoHandler())
                    //                }
                    channel.pipeline.addHandler(NIOSSLServerHandler(context: sslContext)).flatMap {
                        // Right after the SSL handler, we can configure the HTTP/2 pipeline.
                        channel.configureHTTP2Pipeline(mode: .server) { (streamChannel) -> EventLoopFuture<Void> in
                            // For every HTTP/2 stream that the client opens, we put in the `HTTP2ToHTTP1ServerCodec` which
                            // transforms the HTTP/2 frames to the HTTP/1 messages from the `NIOHTTP1` module.
                            streamChannel.pipeline.addHandler(HTTP2FramePayloadToHTTP1ServerCodec()).flatMap { () -> EventLoopFuture<Void> in
                                // And lastly, we put in our very basic HTTP server :).
                                streamChannel.pipeline.addHandler(HTTP1TestServer())
                            }.flatMap { () -> EventLoopFuture<Void> in
                                streamChannel.pipeline.addHandler(ErrorHandler())
                            }
                        }
                    }.flatMap { (_: HTTP2StreamMultiplexer) in
                        return channel.pipeline.addHandler(ErrorHandler())
                    }
                }
            }
            .childChannelOption(ChannelOptions.socket(IPPROTO_TCP, TCP_NODELAY), value: 1)
            .childChannelOption(ChannelOptions.socket(SocketOptionLevel(SOL_SOCKET), SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
    }
}
