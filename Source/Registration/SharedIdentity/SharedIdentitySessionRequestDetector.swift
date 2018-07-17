//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

import UIKit

/**
 * An object that detects shared identity session request wihtin the pasteboard.
 *
 * A session request is a string formatted as `wire-[UUID]`.
 */

@objc public final class SharedIdentitySessionRequestDetector: NSObject {

    private let pasteboard: Pasteboard
    private let processQueue = DispatchQueue(label: "WireSyncEngine.SharedIdentitySessionRequestDetector")

    // MARK: - Initialization

    /// Returns the detector that uses the system pasteboard to detect session requests.
    @objc public static let shared = SharedIdentitySessionRequestDetector(pasteboard: UIPasteboard.general)

    /// Creates a detector that uses the specified pasteboard to detect session requests.
    public init(pasteboard: Pasteboard) {
        self.pasteboard = pasteboard
    }

    // MARK: - Detection

    /**
     * Tries to extract the session request code from the current pasteboard.
     *
     * The processing will be done on a background queue, and the completion
     * handler will be called on the main thread with the result.
     */

<<<<<<< HEAD
    @objc public func detectCopiedRequestCode(_ completionHandler: @escaping (String?) -> Void) {
        func complete(_ code: String?) {
=======
    @objc public func detectCopiedRequestCode(_ completionHandler: @escaping (UUID?) -> Void) {
        func complete(_ code: UUID?) {
>>>>>>> develop
            DispatchQueue.main.async {
                completionHandler(code)
            }
        }

        processQueue.async {
            guard let text = self.pasteboard.text else {
                complete(nil)
                return
            }

<<<<<<< HEAD
            guard SharedIdentitySessionRequestDetector.isValidRequestCode(in: text) else {
                complete(nil)
                return
            }

            complete(text)
=======
            let code = self.detectRequestCode(in: text)
            complete(code)
>>>>>>> develop
        }
    }

    /**
     * Tries to extract the session request code from the user input.
     */

<<<<<<< HEAD
    @objc public static func isValidRequestCode(in string: String) -> Bool {
        guard let prefixRange = string.range(of: "wire-") else {
            return false
        }

        let codeString = string[prefixRange.upperBound ..< string.endIndex]
        return UUID(uuidString: String(codeString)) != nil
=======
    @objc public func detectRequestCode(in string: String) -> UUID? {
        guard let prefixRange = string.range(of: "wire-") else {
            return nil
        }

        let codeString = string[prefixRange.upperBound ..< string.endIndex]
        return UUID(uuidString: String(codeString))
>>>>>>> develop
    }

}
