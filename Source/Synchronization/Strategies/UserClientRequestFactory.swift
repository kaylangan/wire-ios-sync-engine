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
import Cryptobox

enum UserClientRequestError: Error {
    case noPreKeys
    case noLastPreKey
    case clientNotRegistered
}

//TODO: when we should update last pre key or signaling keys?

open class UserClientRequestFactory {
    
    public init(keysCount: UInt16 = 100) {
        self.keyCount = keysCount
    }
    
    open let keyCount : UInt16

    open func registerClientRequest(_ client: UserClient, credentials: ZMEmailCredentials?, authenticationStatus: ZMAuthenticationStatus) throws -> ZMUpstreamRequest {
        
        let (preKeysPayloadData, preKeysRangeMax) = try payloadForPreKeys(client)
        let (signalingKeysPayloadData, signalingKeys) = payloadForSignalingKeys()
        let lastPreKeyPayloadData = try payloadForLastPreKey(client)
        
        var payload: [String: AnyObject] = [
            "type": client.type,
            "label": (client.label ?? ""),
            "model": (client.model ?? ""),
            "class": (client.deviceClass ?? ""),
            "lastkey": lastPreKeyPayloadData,
            "prekeys": preKeysPayloadData,
            "sigkeys": signalingKeysPayloadData,
            "cookie" : ((authenticationStatus.cookieLabel.characters.count != 0) ? authenticationStatus.cookieLabel : "")
        ]
         
        if let password = credentials?.password {
            payload["password"] = password as AnyObject?
        }
        
        let request = ZMTransportRequest(path: "/clients", method: ZMTransportRequestMethod.methodPOST, payload: payload)
        request.addCompletionHandler(storeMaxRangeID(client, maxRangeID: preKeysRangeMax))
        request.addCompletionHandler(storeAPSSignalingKeys(client, signalingKeys: signalingKeys))
        
        let upstreamRequest = ZMUpstreamRequest(transportRequest: request)
        return upstreamRequest
    }
    
    
    func storeMaxRangeID(_ client: UserClient, maxRangeID: UInt16) -> ZMCompletionHandler {
        let completionHandler = ZMCompletionHandler(onGroupQueue: client.managedObjectContext!, block: { response in
            if response.result == .Success {
                client.preKeysRangeMax = Int64(maxRangeID)
            }
        })
        return completionHandler
    }
    
    func storeAPSSignalingKeys(_ client: UserClient, signalingKeys: SignalingKeys) -> ZMCompletionHandler {
        let completionHandler = ZMCompletionHandler(onGroupQueue: client.managedObjectContext!, block: { response in
            if response.result == .Success {
                client.apsDecryptionKey = signalingKeys.decryptionKey
                client.apsVerificationKey = signalingKeys.verificationKey
                client.needsToUploadSignalingKeys = false
            }
        })
        return completionHandler
    }
    
    internal func payloadForPreKeys(_ client: UserClient, startIndex: UInt16 = 0) throws -> (payload: [NSDictionary], maxRange: UInt16) {
        //we don't want to generate new prekeys if we already have them
        do {
            let preKeys = try client.keysStore.generateMoreKeys(keyCount, start: startIndex)
            guard preKeys.count > 0 else {
                throw UserClientRequestError.noPreKeys
            }
            let preKeysPayloadData : [[String : AnyObject]] = preKeys.map {
                ["key": $0.prekey, "id": NSNumber(unsignedShort: $0.id)]
            }
            return (preKeysPayloadData, preKeys.last!.id)
        }
        catch {
            throw UserClientRequestError.noPreKeys
        }
    }
    
    internal func payloadForLastPreKey(_ client: UserClient) throws -> [String: AnyObject] {
        do {
            let lastKey = try client.keysStore.lastPreKey()
            let lastPreKeyString = lastKey
            let lastPreKeyPayloadData : [String: AnyObject] = ["key": lastPreKeyString, "id": NSNumber(unsignedShort: UserClientKeysStore.MaxPreKeyID+1)]
            return lastPreKeyPayloadData
        } catch  {
            throw UserClientRequestError.noLastPreKey
        }
    }
    
    internal func payloadForSignalingKeys() -> (payload: [String: String?], signalingKeys: SignalingKeys) {
        let signalingKeys = APSSignalingKeysStore.createKeys()
        let payload = ["enckey": (signalingKeys.decryptionKey as NSData).base64String(), "mackey": (signalingKeys.verificationKey as NSData).base64String()]
        return (payload, signalingKeys)
    }
    
    open func updateClientPreKeysRequest(_ client: UserClient) throws -> ZMUpstreamRequest {
        if let remoteIdentifier = client.remoteIdentifier {
            let startIndex = UInt16(client.preKeysRangeMax)
            let (preKeysPayloadData, preKeysRangeMax) = try payloadForPreKeys(client, startIndex: startIndex)
            let payload: [String: AnyObject] = [
                "prekeys": preKeysPayloadData
            ]
            let request = ZMTransportRequest(path: "/clients/\(remoteIdentifier)", method: ZMTransportRequestMethod.MethodPUT, payload: payload)
            request.addCompletionHandler(storeMaxRangeID(client, maxRangeID: preKeysRangeMax))

            return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientNumberOfKeysRemainingKey), transportRequest: request, userInfo: nil)
        }
        throw UserClientRequestError.clientNotRegistered
    }
    
    open func updateClientSignalingKeysRequest(_ client: UserClient) throws -> ZMUpstreamRequest {
        if let remoteIdentifier = client.remoteIdentifier {
            let (signalingKeysPayloadData, signalingKeys) = payloadForSignalingKeys()
            let payload: [String: AnyObject] = [
                "sigkeys": signalingKeysPayloadData as AnyObject,
                "prekeys": [] // NOTE backend always expects 'prekeys' to be present atm
            ]
            let request = ZMTransportRequest(path: "/clients/\(remoteIdentifier)", method: ZMTransportRequestMethod.MethodPUT, payload: payload)
            request.addCompletionHandler(storeAPSSignalingKeys(client, signalingKeys: signalingKeys))
            
            return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientNeedsToUpdateSignalingKeysKey), transportRequest: request, userInfo: nil)
        }
        throw UserClientRequestError.clientNotRegistered
    }
    
    /// Password needs to be set
    open func deleteClientRequest(_ client: UserClient, credentials: ZMEmailCredentials) -> ZMUpstreamRequest! {
        let payload = [
            "email" : credentials.email!,
            "password" : credentials.password!
        ]
        let request =  ZMTransportRequest(path: "/clients/\(client.remoteIdentifier)", method: ZMTransportRequestMethod.MethodDELETE, payload: payload)
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMUserClientMarkedToDeleteKey), transportRequest: request)
    }
    
    open func fetchClientsRequest() -> ZMTransportRequest! {
        return ZMTransportRequest(getFromPath: "/clients")
    }
    
}
