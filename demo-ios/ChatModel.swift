import Foundation
import AblyRealtime

public protocol ChatModelDelegate {
    func chatModel(chatModel: ChatModel, connectionStateChanged: ARTConnectionStateChange)
    func chatModelLoadingHistory(chatModel: ChatModel)
    func chatModelDidFinishSendingMessage(chatModel: ChatModel)
    func chatModel(chatModel: ChatModel, didReceiveMessage message: ARTMessage)
    func chatModel(chatModel: ChatModel, didReceiveError error: ARTErrorInfo)
    func chatModel(chatModel: ChatModel, historyDidLoadWithMessages: [ARTBaseMessage])
    func chatModel(chatModel: ChatModel, membersDidUpdate: [ARTPresenceMessage], presenceMessage: ARTPresenceMessage)
}

public class ChatModel {
    private var ablyClientOptions: ARTClientOptions
    private var ablyRealtime: ARTRealtime?
    private var channel: ARTRealtimeChannel?
    private var isUserTyping = false
    
    public var clientId: String
    public var delegate: ChatModelDelegate?
    public var hasAppJoined = false
    
    public init(clientId: String) {
        self.clientId = clientId
        
        ablyClientOptions = ARTClientOptions()
        ablyClientOptions.authUrl = NSURL(string: "https://www.ably.io/ably-auth/token-details/demos")
        ablyClientOptions.clientId = clientId
        ablyClientOptions.logLevel = .Verbose
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatModel.applicationWillResignActiveEventReceived(_:)),
                                                         name: "applicationWillResignActive",
                                                         object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatModel.applicationWillEnterForegroundEventReceived(_:)),
                                                         name: "applicationWillEnterForeground",
                                                         object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(ChatModel.applicationWillEnterForegroundEventReceived(_:)),
                                                         name: "applicationDidBecomeActive",
                                                         object: nil)
    }
    
    public func connect() {
        detachHandlers()
        
        self.ablyRealtime = ARTRealtime(options: self.ablyClientOptions)
        let realtime = self.ablyRealtime!
        
        realtime.connection.on { stateChange in
            if let stateChange = stateChange {
                self.delegate?.chatModel(self, connectionStateChanged: stateChange)
                
                switch stateChange.current {
                case .Disconnected:
                    self.attemptReconnect(5000)
                case .Suspended:
                    self.attemptReconnect(15000)
                default:
                    break
                }
            }
        }
        
        self.channel = realtime.channels.get("mobile:chat")
        self.joinChannel()
    }
    
    // Explicitly reconnect to Ably and joins channel
    public func reconnect() {
        self.connect()
    };
    
    // Leaves channel by disconnecting from Ably
    public func disconnect() {
        self.ablyRealtime?.connection.close()
    };

    public func publishMessage(message: String) {
        self.channel?.publish(self.clientId, data: message, clientId: self.clientId) { error in
            guard error == nil else {
                self.signalError(error!)
                return
            }
            
            self.delegate?.chatModelDidFinishSendingMessage(self)
        }
    }
    
    public func sendTypingNotification(typing: Bool) {
        // Don't send a 'is typing' notification if user is already typing
        if (self.isUserTyping && typing) {
            return;
        }
        
        self.channel?.presence.update(["isTyping": typing])
        self.isUserTyping = typing;
    }
    
    private func detachHandlers() {
        
    }
    
    private func attemptReconnect(delay: Double) {
        self.delay(delay) {
            self.ablyRealtime?.connect()
        }
    }
    
    private func joinChannel() {
        guard let channel = self.channel else { return }
        let presence = channel.presence

        self.delegate?.chatModelLoadingHistory(self)
        channel.attach()
        
        channel.subscribe { self.delegate?.chatModel(self, didReceiveMessage: $0) }
        presence.subscribe(self.membersChanged)
        
        presence.enter(nil) { error in
            guard error == nil else {
                self.signalError(error!)
                return
            }
            
            self.loadHistory()
        }
        
        channel.once(ARTChannelEvent.Detached, callback: self.didChannelLoseState)
        channel.once(ARTChannelEvent.Failed, callback: self.didChannelLoseState)
    }
    
    private func membersChanged(msg: ARTPresenceMessage) {
        self.channel?.presence.get() { (result, error) in
            guard error == nil else {
                self.signalError(ARTErrorInfo.createWithNSError(error!))
                return
            }
            
            let members = result ?? [ARTPresenceMessage]()
            self.delegate?.chatModel(self, membersDidUpdate: members, presenceMessage: msg)
        }
    }
    
    private func loadHistory() {
        var messageHistory: [ARTMessage]? = nil
        var presenceHistory: [ARTPresenceMessage]? = nil
        
        func displayIfReady() {
            guard messageHistory != nil && presenceHistory != nil else { return }

            var combinedMessageHistory = [ARTBaseMessage]()
            combinedMessageHistory.appendContentsOf(messageHistory! as [ARTBaseMessage])
            combinedMessageHistory.appendContentsOf(presenceHistory! as [ARTBaseMessage])
            combinedMessageHistory.sortInPlace({ (msg1, msg2) -> Bool in
                return msg1.timestamp!.compare(msg2.timestamp!) == .OrderedAscending
            })
            
            self.delegate?.chatModel(self, historyDidLoadWithMessages: combinedMessageHistory)
        };
        
        self.getMessagesHistory { messages in
            messageHistory = messages;
            displayIfReady();
        }
        
        self.getPresenceHistory { presenceMessages in
            presenceHistory = presenceMessages;
            displayIfReady();
        }
    }
    
    private func getMessagesHistory(callback: [ARTMessage] -> Void) {
        do {
            try self.channel!.history(self.createHistoryQueryOptions()) { (result, error) in
                guard error == nil else {
                    self.signalError(ARTErrorInfo.createWithNSError(error!))
                    return
                }
                
                let items = result?.items as? [ARTMessage] ?? [ARTMessage]()
                callback(items)
            }
        }
        catch let error as NSError {
            self.signalError(ARTErrorInfo.createWithNSError(error))
        }
    }
    
    private func getPresenceHistory(callback: [ARTPresenceMessage] -> Void) {
        do {
            try self.channel!.presence.history(self.createHistoryQueryOptions()) { (result, error) in
                guard error == nil else {
                    self.signalError(ARTErrorInfo.createWithNSError(error!))
                    return
                }
                
                let items = result?.items as? [ARTPresenceMessage] ?? [ARTPresenceMessage]()
                callback(items)
            }
        }
        catch let error as NSError {
            self.signalError(ARTErrorInfo.createWithNSError(error))
        }
    }

    private func createHistoryQueryOptions() -> ARTRealtimeHistoryQuery {
        let query = ARTRealtimeHistoryQuery()
        query.limit = 50
        query.direction = .Backwards
        query.untilAttach = true
        return query
    }

    private func didChannelLoseState(error: ARTErrorInfo?) {
        self.channel?.unsubscribe()
        self.channel?.presence.unsubscribe()
        self.ablyRealtime?.connection.once(.Connected) { state in
            self.joinChannel()
        }
    }
    
    private func signalError(error: ARTErrorInfo) {
        self.delegate?.chatModel(self, didReceiveError: error)
    }
    
    private func delay(delay: Double, block: () -> Void) {
        let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delay * Double(NSEC_PER_SEC)))
        dispatch_after(time, dispatch_get_main_queue(), block)
    }

    @objc private func applicationWillResignActiveEventReceived(notification: NSNotification) {
        self.disconnect()
    }
    
    @objc private func applicationWillEnterForegroundEventReceived(notification: NSNotification) {
        self.reconnect()
    }
}
