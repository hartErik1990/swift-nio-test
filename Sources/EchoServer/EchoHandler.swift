//
//  EchoHandler.swift
//  EchoServer
//
//  Created by Jonathan Wong on 4/25/18.
//

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
import NIOHTTP2

class EchoHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer
    
    func channelRead(ctx: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        let readableBytes = buffer.readableBytes
        if let received = buffer.readString(length: readableBytes) {
            print(received)
        }
        
        ctx.write(data, promise: nil)
    }
    
    func channelReadComplete(ctx: ChannelHandlerContext) {
        ctx.flush()
    }
    
    func errorCaught(ctx: ChannelHandlerContext, error: Error) {
        print("error: \(error.localizedDescription)")
        ctx.close(promise: nil)
    }
}

final class HTTP1TestServer: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard case .end = self.unwrapInboundIn(data) else {
            return
        }
        
        // Insert an event loop tick here. This more accurately represents real workloads in SwiftNIO, which will not
        // re-entrantly write their response frames.
        context.eventLoop.execute {
            context.channel.getOption(HTTP2StreamChannelOptions.streamID).flatMap { (streamID) -> EventLoopFuture<Void> in
                var headers = HTTPHeaders()
                // headers.add(name: "content-length", value: "5")
                headers.add(name: "x-stream-id", value: String(Int(streamID)))
                context.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.head(HTTPResponseHead(version: .init(major: 2, minor: 0), status: .ok, headers: headers))), promise: nil)
                
                var buffer = context.channel.allocator.buffer(capacity: 12)
                buffer.writeStaticString("hello there")
                context.channel.write(self.wrapOutboundOut(HTTPServerResponsePart.body(.byteBuffer(buffer))), promise: nil)
                return context.channel.writeAndFlush(self.wrapOutboundOut(HTTPServerResponsePart.end(nil)))
            }.whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
    
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("error: \(error.localizedDescription)")
        context.close(promise: nil)
    }
}


final class ErrorHandler: ChannelInboundHandler {
    typealias InboundIn = Never
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        print("Server received error: \(error)")
        context.close(promise: nil)
    }
}
