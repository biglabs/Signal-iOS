//  Created by Michael Kirk on 12/13/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

import Foundation
import PromiseKit
import CallKit

protocol CallUIAdaptee {
    var notificationsAdapter: CallNotificationsAdapter { get }
    var hasManualRinger: Bool { get }

    func startOutgoingCall(_ call: SignalCall)
    func reportIncomingCall(_ call: SignalCall, callerName: String)
    func reportMissedCall(_ call: SignalCall, callerName: String)
    func answerCall(_ call: SignalCall)
    func declineCall(_ call: SignalCall)
    func recipientAcceptedCall(_ call: SignalCall)
    func endCall(_ call: SignalCall)
    func toggleMute(call: SignalCall, isMuted: Bool)
}

// Shared default implementations
extension CallUIAdaptee {
    internal func showCall(_ call: SignalCall) {
        let callNotificationName = CallService.callServiceActiveCallNotificationName()
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: callNotificationName), object: call)
    }

    internal func reportMissedCall(_ call: SignalCall, callerName: String) {
        notificationsAdapter.presentMissedCall(call, callerName: callerName)
    }
}

/**
 * Notify the user of call related activities.
 * Driven by either a CallKit or System notifications adaptee
 */
class CallUIAdapter {

    let TAG = "[CallUIAdapter]"
    private let adaptee: CallUIAdaptee
    private let contactsManager: OWSContactsManager
    private let audioService: CallAudioService

    required init(callService: CallService, contactsManager: OWSContactsManager, notificationsAdapter: CallNotificationsAdapter) {
        self.contactsManager = contactsManager
        if Platform.isSimulator {
            // CallKit doesn't seem entirely supported in simulator.
            // e.g. you can't receive calls in the call screen.
            // So we use the non-CallKit call UI.
            Logger.info("\(TAG) choosing non-callkit adaptee for simulator.")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else if #available(iOS 10.0, *) {
            Logger.info("\(TAG) choosing callkit adaptee for iOS10+")
            adaptee = CallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        } else {
            Logger.info("\(TAG) choosing non-callkit adaptee for older iOS")
            adaptee = NonCallKitCallUIAdaptee(callService: callService, notificationsAdapter: notificationsAdapter)
        }

        audioService = CallAudioService(handleRinging: adaptee.hasManualRinger)
    }

    internal func reportIncomingCall(_ call: SignalCall, thread: TSContactThread) {
        call.addObserverAndSyncState(observer: audioService)

        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportIncomingCall(call, callerName: callerName)
    }

    internal func reportMissedCall(_ call: SignalCall) {
        let callerName = self.contactsManager.displayName(forPhoneIdentifier: call.remotePhoneNumber)
        adaptee.reportMissedCall(call, callerName: callerName)
    }

    internal func startOutgoingCall(handle: String) -> SignalCall {
        let call = SignalCall.outgoingCall(localId: UUID(), remotePhoneNumber: handle)
        call.addObserverAndSyncState(observer: audioService)

        adaptee.startOutgoingCall(call)
        return call
    }

    internal func answerCall(_ call: SignalCall) {
        adaptee.answerCall(call)
    }

    internal func declineCall(_ call: SignalCall) {
        adaptee.declineCall(call)
    }

    internal func recipientAcceptedCall(_ call: SignalCall) {
        adaptee.recipientAcceptedCall(call)
    }

    internal func endCall(_ call: SignalCall) {
        adaptee.endCall(call)
    }

    internal func showCall(_ call: SignalCall) {
        adaptee.showCall(call)
    }

    internal func toggleMute(call: SignalCall, isMuted: Bool) {
        // With CallKit, muting is handled by a CXAction, so it must go through the adaptee
        adaptee.toggleMute(call: call, isMuted: isMuted)
    }

    internal func toggleSpeakerphone(call: SignalCall, isEnabled: Bool) {
        // Speakerphone is not handled by CallKit (e.g. there is no CXAction), so we handle it w/o going through the 
        // adaptee, relying on the AudioService CallObserver to put the system in a state consistent with the call's 
        // assigned property.
        call.isSpeakerphoneEnabled = isEnabled
    }

    // CallKit handles ringing state on it's own. But for non-call kit we trigger ringing start/stop manually.
    internal var hasManualRinger: Bool {
        return adaptee.hasManualRinger
    }
}
