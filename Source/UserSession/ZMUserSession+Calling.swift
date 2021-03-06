//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

@objc extension ZMUserSession {
    
    public var callCenter : WireCallCenterV3? {
        return managedObjectContext.zm_callCenter
    }
    
    internal var callNotificationStyle : CallNotificationStyle {
        return sessionManager.callNotificationStyle
    }
    
    @available(iOS 10.0, *)
    internal var callKitDelegate : CallKitDelegate? {
        return sessionManager.callKitDelegate
    }
    
    @objc var useConstantBitRateAudio : Bool {
        set {
            managedObjectContext.zm_useConstantBitRateAudio = newValue
            callCenter?.useConstantBitRateAudio = newValue
        }
        
        get {
            return managedObjectContext.zm_useConstantBitRateAudio
        }
    }
    
}
