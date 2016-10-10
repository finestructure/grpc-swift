/*
 *
 * Copyright 2016, Google Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
import Foundation
import gRPC
import QuickProto

class EchoServer {
  private var address: String
  private var server: Server

  init(address:String, secure:Bool) {
    gRPC.initialize()
    self.address = address
    if secure {
      let certificateURL = Bundle.main.url(forResource: "ssl", withExtension: "crt")!
      let certificate = try! String(contentsOf: certificateURL)
      let keyURL = Bundle.main.url(forResource: "ssl", withExtension: "key")!
      let key = try! String(contentsOf: keyURL)
      self.server = gRPC.Server(address:address, key:key, certs:certificate)
    } else {
      self.server = gRPC.Server(address:address)
    }
  }

  func start() {
    let fileDescriptorSet = FileDescriptorSet(filename:"echo.out")
    print("Server Starting")
    print("GRPC version " + gRPC.version())

     server.run {(requestHandler) in
      print("Received request to " + requestHandler.host()
        + " calling " + requestHandler.method()
        + " from " + requestHandler.caller())

      // NONSTREAMING
      if (requestHandler.method() == "/echo.Echo/Get") {
        requestHandler.receiveMessage(initialMetadata:Metadata())
        {(requestData) in
          if let requestData = requestData,
            let requestMessage =
            fileDescriptorSet.readMessage("EchoRequest", data: requestData) {
            requestMessage.forOneField("text") {(field) in
              let replyMessage = fileDescriptorSet.makeMessage("EchoResponse")!
              replyMessage.addField("text", value:"Swift nonstreaming echo " + field.string())
              requestHandler.sendResponse(message:replyMessage.data(),
                                          trailingMetadata:Metadata())
            }
          }
        }
      }

      // STREAMING
      if (requestHandler.method() == "/echo.Echo/Update") {
        requestHandler.sendMetadata(
          initialMetadata: Metadata(),
          completion: {

            self.handleMessage(
              fileDescriptorSet: fileDescriptorSet,
              requestHandler: requestHandler)

            // we seem to never get this, but I'm told it's what we're supposed to do
            requestHandler.receiveClose() {
              requestHandler.sendStatus(trailingMetadata: Metadata(), completion: {
                print("status sent")
                requestHandler.shutdown()
              })
            }
          }
        )
      }
    }
  }

  func handleMessage(fileDescriptorSet: FileDescriptorSet,
                     requestHandler: Handler) {
    requestHandler.receiveMessage()
      {(requestData) in
        if let requestData = requestData,
          let requestMessage = fileDescriptorSet.readMessage("EchoRequest", data:requestData) {
          requestMessage.forOneField("text") {(field) in
            let replyMessage = fileDescriptorSet.makeMessage("EchoResponse")!
            replyMessage.addField("text", value:"Swift streaming echo " + field.string())
            requestHandler.sendResponse(message:replyMessage.data()) {
              // after we've sent our response, prepare to handle another message
              self.handleMessage(fileDescriptorSet:fileDescriptorSet, requestHandler:requestHandler)
            }
          }
        } else {
          // if we get an empty message (nil buffer), we close the connection
          requestHandler.sendStatus(trailingMetadata: Metadata(), completion: {
            print("status sent")
            requestHandler.shutdown()
          })
        }
    }
  }
}