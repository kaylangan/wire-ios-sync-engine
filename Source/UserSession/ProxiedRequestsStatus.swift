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

/// Keeps track of which requests to send to the backend
open class ProxiedRequestsStatus: NSObject {
    
    public typealias Request = (type:ProxiedRequestType, path: String, method: ZMTransportRequestMethod, callback: ((Data?, HTTPURLResponse?, NSError?) -> Void)?)

    /// List of requests to be sent to backend
    open var pendingRequests : [Request] = []
    
    open func addRequest(_ type:ProxiedRequestType, path: String, method: ZMTransportRequestMethod = .methodGET, callback: ((Data?, HTTPURLResponse?, NSError?) -> Void)?) {
        pendingRequests.append(Request(type, path, method, callback))
    }
}
