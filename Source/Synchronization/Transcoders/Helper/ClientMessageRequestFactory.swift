// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


import Foundation
import ZMTransport
import zimages

private let zmLog = ZMSLog(tag: "Network")

open class ClientMessageRequestFactory: NSObject {
    
    let protobufContentType = "application/x-protobuf"
    let octetStreamContentType = "application/octet-stream"
    
    open func upstreamRequestForMessage(_ message: ZMClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        return upstreamRequestForEncryptedClientMessage(message, forConversationWithId: conversationId);
    }
    
    open func upstreamRequestForAssetMessage(_ format: ZMImageFormat, message: ZMAssetClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
            return upstreamRequestForEncryptedImageMessage(format, message: message, forConversationWithId: conversationId);
    }
    
    fileprivate func upstreamRequestForEncryptedClientMessage(_ message: ZMClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        let path = "/" + ["conversations", (conversationId as NSUUID).transportString(), "otr", "messages"].joined(separator: "/")
        guard let dataAndMissingClientStrategy = message.encryptedMessagePayloadData() else {
            return nil
        }
        let pathWithStrategy = self.pathWithMissingClientStrategy(path, strategy: dataAndMissingClientStrategy.strategy)
        let request = ZMTransportRequest(path: pathWithStrategy, method: .MethodPOST, binaryData: dataAndMissingClientStrategy.data, type: protobufContentType, contentDisposition: nil)
        var debugInfo = "\(message.genericMessage)"
        if let genericMessage = message.genericMessage , genericMessage.hasExternal() { debugInfo = "External message: " + debugInfo }
        request.appendDebugInformation(debugInfo)
        return request
    }

    fileprivate func upstreamRequestForEncryptedImageMessage(_ format: ZMImageFormat, message: ZMAssetClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {

        let genericMessage = format == .Medium ? message.imageAssetStorage!.mediumGenericMessage : message.imageAssetStorage!.previewGenericMessage
        let format = ImageFormatFromString(genericMessage!.image.tag)
        let isInline = message.imageAssetStorage!.isInlineForFormat(format)
        let hasAssetId = message.assetId != nil
        
        if isInline || !hasAssetId {
            //inline messsages and new messages should be always posted with image data
            //and using endpoint for image asset upload
            return upstreamRequestForInsertedEncryptedImageMessage(format, message: message, forConversationWithId: conversationId);
        }
        else if hasAssetId {
            //not inline messages updated with missing clients should use retry endpoint and not send message data
            return upstreamRequestForUpdatedEncryptedImageMessage(format, message: message, forConversationWithId: conversationId)
        }
        return nil
    }
    
    // request for first upload and reupload inline images
    fileprivate func upstreamRequestForInsertedEncryptedImageMessage(_ format: ZMImageFormat, message: ZMAssetClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        if let imageData = message.imageAssetStorage!.imageDataForFormat(format, encrypted: true) {
            let path = "/" +  ["conversations", (conversationId as NSUUID).transportString(), "otr", "assets"].joined(separator: "/")
            let metaData = message.encryptedMessagePayloadForImageFormat(format)!
            let request = ZMTransportRequest.multipartRequestWithPath(path, imageData: imageData, metaData: metaData.data(), metaDataContentType: protobufContentType, mediaContentType: octetStreamContentType)
            request.appendDebugInformation("\(message.imageAssetStorage!.genericMessageForFormat(format))")
            request.appendDebugInformation("\(metaData)")
            request.forceToBackgroundSession()
            return request
        }
        return nil
    }
    
    // request to reupload image (not inline)
    fileprivate func upstreamRequestForUpdatedEncryptedImageMessage(_ format: ZMImageFormat, message: ZMAssetClientMessage, forConversationWithId conversationId: UUID) -> ZMTransportRequest? {
        let path = "/" + ["conversations", conversationId.transportString(), "otr", "assets", message.assetId!.transportString()].joinWithSeparator("/")
        let metaData = message.encryptedMessagePayloadForImageFormat(format)!
        let request = ZMTransportRequest(path: path, method: ZMTransportRequestMethod.MethodPOST, binaryData: metaData.data(), type: protobufContentType, contentDisposition: nil)
        request.appendDebugInformation("\(message.imageAssetStorage!.genericMessageForFormat(format))")
        request.appendDebugInformation("\(metaData)")
        request.forceToBackgroundSession()
        return request
    }
    
    open func requestToGetAsset(_ assetId: String, inConversation conversationId: UUID, isEncrypted: Bool) -> ZMTransportRequest {
        let path = "/" + ["conversations", (conversationId as NSUUID).transportString()!, isEncrypted ? "otr" : "", "assets", assetId].joined(separator: "/")
        let request = ZMTransportRequest.imageGet(fromPath: path)
        request.forceToBackgroundSession()
        return request
    }
    
    fileprivate func pathWithMissingClientStrategy(_ originalPath: String, strategy: MissingClientsStrategy) -> String {
        switch strategy {
        case .DoNotIgnoreAnyMissingClient:
            return originalPath
        case .IgnoreAllMissingClients:
            return originalPath + "?ignore_missing"
        case .IgnoreAllMissingClientsNotFromUser(let user):
            return originalPath + "?report_missing=\(user.remoteIdentifier?.transportString() ?? "")"
        }
    }
    
}

// MARK: - Testing Helper
extension ZMClientMessage {
    public var encryptedMessagePayloadDataOnly : NSData? {
        return self.encryptedMessagePayloadData()?.data
    }
}
