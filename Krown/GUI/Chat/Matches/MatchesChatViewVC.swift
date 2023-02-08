//
//  MatchesChatViewVC.swift
//  Krown
//
//  Created by macOS on 03/02/22.
//  Copyright © 2022 KrownUnity. All rights reserved.
//

import UIKit
import SwiftUI
import XMPPFramework
import Alamofire
import AlamofireImage
import MBProgressHUD
import Koloda
import MessageKit
import MapKit
import IQKeyboardManagerSwift
import InputBarAccessoryView
import Agrume
import Photos
import SDWebImage
weak var hostingController: UIViewController?    // << wraps reference



class MatchesChatViewVC: MessagesViewController, OneMessageDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate  {
    
    let refreshControl = UIRefreshControl()
    var messageListHistory: [MessageObject] = []
    var messageList: [MessageObject] = []
    var isTyping = false
    var recipientXMPP: XMPPUserCoreDataStorageObject?
    var matchObject = MatchObject()
    var personObject = PersonObject()
    var timer: Timer?
    var kolodaView = KolodaView()
    var kolodaViewNumberOfCards = 0
    var mainController = MainController()
    var selectedIndexPath: IndexPath!
    var messageIdInNewMessage = String() // used for storing newly created messageId string when you send a new message
    var label = UILabel()
    var chatImageLocalID = String() // used for storing local ID of the image that is opened in chat
    var keyboardHeight : CGFloat = CGFloat()
    var allPhotos = PHFetchResult<PHAsset>() // representing camera roll
    // UI Elements
    var arrowButtonForProfile = UIButton()
    var encouragementView = UIView()
    var userPictureView = UIImageView()
    var imgOtherUser : UIImage?
    var imgYouUser : UIImage?
    var isFromSwiftUI : Bool = Bool()
    var blockview = UIView()
    var isFromMatchVC = false
    var selectedMessageTypeFromMatch = checkSelectedMessageTypeFromMatch.text
    var strMessageFromMatchVC = ""
    var imageMessage : UIImage?
    
    var looperImage: Looper? {
        didSet {
            configLooperImage()
        }
    }
    func configLooperImage() {
        looperImage?.start(in: userPictureView.layer)
    }
    var bottomView : BottomChat = BottomChat()
    // Agrume custom overlay view
    private var agrume: Agrume?
    
    private lazy var overlayView: AgrumeCustomOverlayView = {
        let overlay = AgrumeCustomOverlayView()
        overlay.delegate = self
        return overlay
    }()
    var y : CGFloat = CGFloat()
    let defaults = UserDefaults.standard
    var photosLocalIdentifiers = UserDefaults.standard.object(forKey: "localIdentifiers") as? [String: String] ?? [String: String]()
    
    func saveLocalIdentifiersInUserDefaults(messageIdString: String, localIdentifier: String) {
        
        self.photosLocalIdentifiers.updateValue(localIdentifier, forKey: messageIdString)
        defaults.set(self.photosLocalIdentifiers, forKey: "localIdentifiers")
    }
    
    func deleteKeyValueFromLocalIdentifiers(messageIdString: String) {
        self.photosLocalIdentifiers.removeValue(forKey: messageIdString)
        defaults.set(self.photosLocalIdentifiers, forKey: "localIdentifiers")
    }
    func customView()
    {
        blockview.frame = self.view.frame
        blockview.backgroundColor = .white
        blockview.bounds = self.view.bounds
        bottomView.isHidden = true
        bottomView.removeFromSuperview()
        label = UILabel(frame: CGRect(x: 0, y: 150, width: self.blockview.frame.size.width, height: 100))
        label.textAlignment = .center
        label.text = "Blocked & Reported"
        label.textColor = UIColor.darkText
        label.font =  UIFont(name: "Avenir Medium", size: 40.0)
        blockview.addSubview(label)
        let imageView = UIImageView(image: UIImage(named: "Ignore Icon-1"))
        imageView.frame = CGRect(x: 0, y: label.frame.size.height, width: 100, height: 100)
        imageView.center = blockview.center

        blockview.addSubview(imageView)

        navigationController?.setNavigationBarHidden(true, animated: false)
        self.view.addSubview(blockview)
        
    }
    func getButtonFromAgrumeToolbar(overlayView: AgrumeCustomOverlayView, tag: Int) -> UIBarButtonItem {
        
        var newButton = UIBarButtonItem()
        var buttonToReturn: [AnyObject]?
        if let buttons = overlayView.toolbar.items {
            buttonToReturn = buttons.filter({
                (x: AnyObject) -> Bool in
                
                if let button = x as? UIBarButtonItem {
                    if button.tag == tag {
                        return true
                    }
                }
                return false
            })
            
            if let button = (buttonToReturn!.first as? UIBarButtonItem) {
                newButton = button
            }
        }
        return newButton
        
    }
    
    //  localIdentifier for the image from chat will be passed
    func agrumeSetup(image: UIImage, background: Background, overlayView: AgrumeCustomOverlayView, chatImageLocalID: String) {
        self.agrume = Agrume(image: image, background: background, overlayView: overlayView)
        overlayView.image = image
        // check if the image with provided localIdentifier already exists in Photos
        let fetchOptions = PHFetchOptions()
        let imageExistsInPhotos = PHAsset.fetchAssets(withLocalIdentifiers: [chatImageLocalID], options: fetchOptions)
        // if the result is count > 1 we are sure there is an image with provided local Identifier in the gallery so we can disable the save button
        if imageExistsInPhotos.count > 0 {
            let saveButtonDisabled = self.getButtonFromAgrumeToolbar(overlayView: overlayView, tag: 1234)
            saveButtonDisabled.isEnabled = false
            saveButtonDisabled.title = "Saved"
            
        } else {
            // if image isn't saved, save button should be enabled
            let saveButtonEnabled = self.getButtonFromAgrumeToolbar(overlayView: overlayView, tag: 1234)
            saveButtonEnabled.isEnabled = true
            saveButtonEnabled.title = "Save"
        }
        
        let button = UIBarButtonItem(barButtonSystemItem: .stop, target: self, action: #selector(agrumeDismiss))
        overlayView.navigationBar.topItem?.leftBarButtonItem = button
        
        self.agrume?.tapBehavior = .toggleOverlayVisibility
        self.agrume?.show(from: self)
    }
    
    @objc func agrumeDismiss() {
        self.agrume?.dismiss()
    }
    
    // helper function to present UIActivityViewController
    func getTopMostViewController() -> UIViewController? {
        var topMostViewController = UIApplication.shared.keyWindow?.rootViewController
        
        while let presentedViewController = topMostViewController?.presentedViewController {
            topMostViewController = presentedViewController
        }
        
        return topMostViewController
    }

    @objc func keyboardWillAppear(notification: NSNotification?) {

        guard let userInfo = notification?.userInfo else { return }

        guard let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue else {
            return
        }
//        let keyboardHeight: CGFloat = keyboardFrame.cgRectValue.height - (self.view.safeAreaInsets.bottom * 2)
        let keyboardHeight: CGFloat = keyboardFrame.cgRectValue.height
        //print("Keyboard show height matcheschatVc - ",keyboardHeight)

        var keyboardAnimationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        if keyboardAnimationDuration == 0 {
            keyboardAnimationDuration = 0.25
        }
        // Animate the constraint changes and scroll to bottom
        UIView.animate(withDuration: keyboardAnimationDuration, animations: { [self] in
            self.view.layoutIfNeeded()
//            if keyboardHeight > 210 {

            
                    if(keyboardHeight < 100)
                    {
//                        self.keyboardHeight = 0
                        bottomView.frame.origin.y = y
                    }else{
                        self.keyboardHeight = keyboardHeight
                        let window = UIApplication.shared.windows.first
                        let safeAreaInset = window?.safeAreaInsets.bottom ?? 0
                        bottomView.frame.origin.y = y - self.keyboardHeight + (safeAreaInset > 0 ? 42 : 0)
                    }
                    self.messagesCollectionView.contentInset.bottom = self.keyboardHeight + 63
//                    self.messagesCollectionView.contentInset.bottom = bottomView.frame.origin.y - 63

                    self.messagesCollectionView.scrollToLastItem()
//            }
        })
        
    }

    @objc func keyboardWillDisappear(notification: NSNotification?) {
        
       
        guard let userInfo = notification?.userInfo else { return }
        var keyboardAnimationDuration = userInfo[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        if keyboardAnimationDuration == 0 {
            keyboardAnimationDuration = 0.25
        }
        // Animate the constraint changes and scroll to bottom
        UIView.animate(withDuration: keyboardAnimationDuration, animations: { [self] in
            self.view.layoutIfNeeded()
            keyboardHeight = 0
            //print("Bottom view y - ",bottomView.frame.origin.y)
            //print("y value - ",y)
            bottomView.frame.origin.y = y-keyboardHeight
        })
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: { [self] in
            messagesCollectionView.contentInset.bottom = 63
            messagesCollectionView.scrollToLastItem()
        })
    }


    @objc override func dismissKeyboard() {
        bottomView.txtChat.resignFirstResponder()
    }
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.navigationBar.isHidden = false
        self.tabBarController?.tabBar.layer.zPosition = -1
        self.tabBarController?.tabBar.isUserInteractionEnabled = false
        self.tabBarController?.tabBar.items?.forEach { $0.isEnabled = false }
        self.tabBarController?.tabBar.alpha = 0
        let tabBar = self.tabBarController?.tabBar
        tabBar?.frame = CGRect(x: 0, y: self.view.frame.height, width: (tabBar?.frame.size.width)!, height:  (tabBar?.frame.size.height)!)
    }
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.tabBarController?.tabBar.isHidden = true
        self.navigationController?.isNavigationBarHidden = false
        navigationController?.hidesBarsOnSwipe = false

        self.view.backgroundColor = UIColor.blue
        
//        registerKeyboardEvents()
        
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillAppear(notification:)), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillDisappear(notification:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        
//        configureKeyboardManager()
//        let tap: UITapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(self.dismissKeyboard))
//        tap.cancelsTouchesInView = false
//        self.messagesCollectionView.addGestureRecognizer(tap)
//        self.messagesCollectionView.backgroundView?.addGestureRecognizer(tap)
        self.messagesCollectionView.keyboardDismissMode = .onDrag
        self.messagesCollectionView.automaticallyAdjustsScrollIndicatorInsets = false

        
        // Fetch messages
        DispatchQueue.global(qos: .userInitiated).async {
            self.getMessages(count: 20) { messages in
                DispatchQueue.main.async {
                    self.messageList = messages
                    self.messagesCollectionView.reloadData()
                    self.messagesCollectionView.scrollToLastItem()
                    self.addOrRemoveEncouragementView()
                    self.callsForMAtchUsers()
                }
            }
        }
        
        // Setup delegates
        messagesCollectionView.messagesDataSource = self
        messagesCollectionView.messagesLayoutDelegate = self
        messagesCollectionView.messagesDisplayDelegate = self
        messagesCollectionView.messageCellDelegate = self
        // To receive messages
        OneMessage.sharedInstance.delegate = self
        // Tell OneMessage that we have an open chat with a user
        OneMessage.sharedInstance.isFriendFromOpenChat = recipientXMPP?.jid
        
        // Due to a bug between iqkeyboardmanager and the messagekit iqmanager is switched off for the chat
        IQKeyboardManager.shared.enable = false

        // SetupNavbar
        setUpCustomNavBar()
        
        // setup background image for chat
        setupBackground()
        
        // Setup of Kolodaview Delegates
        kolodaView.dataSource = self
        kolodaView.delegate = self
        setupKolodaView()
        
        // Setup keyboard
        self.configureInputBarAccessoryView()
        
        // Swiping left to exit view
//        let backSwipe = UISwipeGestureRecognizer(target: self, action: #selector(backBtn))
//        backSwipe.direction =  UISwipeGestureRecognizer.Direction.right
//        self.view.addGestureRecognizer(backSwipe)
        
        // messageInputBar.sendButton.tintColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
        scrollsToLastItemOnKeyboardBeginsEditing = false // default false
        maintainPositionOnKeyboardFrameChanged = false // default false
        
        messagesCollectionView.addSubview(refreshControl)
        refreshControl.addTarget(self, action: #selector(MatchesChatViewVC.loadMoreMessages), for: .valueChanged)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "CaretLeft"),
                                                           style: .plain,
                                                           target: self,
                                                           action: #selector(MatchesChatViewVC.backBtn))
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "flag"),
                                                            style: .plain,
                                                            target: self,
                                                            action: #selector(MatchesChatViewVC.flagBtn))
        navigationItem.leftBarButtonItem?.tintColor = UIColor.slateGrey
        navigationItem.rightBarButtonItem?.tintColor = UIColor.slateGrey
        // Setup observer for refresh
        NotificationCenter.default.addObserver(self, selector: #selector(MatchesChatViewVC.refreshChatMessagesAfterDeletion), name: .refreshChatViewVCafterDeletion, object: nil)
        
        
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
//
        self.navigationController?.interactivePopGestureRecognizer!.delegate = self
        navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        self.navigationController?.isNavigationBarHidden = false

        
        // This code is added because of this issue https://github.com/MessageKit/MessageKit/issues/751
        self.messagesCollectionView.contentInset.bottom = 63
        self.messagesCollectionView.scrollToLastItem()
        kolodaView.frame = CGRect(x: (self.view.frame.width - 343) / 2, y: 100, width: 343, height: 540)
        // Add or remce encouragement view when no messages present
        addOrRemoveEncouragementView()
    }
    //MARK: - Gesture methods
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    {
        if messagesCollectionView.bounds.contains(touch.location(in: messagesCollectionView))
        {
            
           /* if let swipeGesture = gestureRecognizer as? UISwipeGestureRecognizer
            {
                switch swipeGesture.direction
                {
                    case UISwipeGestureRecognizer.Direction.right:
                            print("Swiped right")
                            return false
                    case UISwipeGestureRecognizer.Direction.down:
                            print("Swiped down")
                    case UISwipeGestureRecognizer.Direction.left:
                            print("Swiped left")
                    case UISwipeGestureRecognizer.Direction.up:
                            print("Swiped up")
                    default:
                        break
                }
                
            }*/
            return false
        }
        return true
    }
    //MARK: -
    override func viewDidDisappear(_ animated: Bool) {
        // Due to a bug between iqkeyboardmanager and the messagekit iqmanager is switched off for the chat
        IQKeyboardManager.shared.enable = false
        // Tell OneMessage that there is no open window for the chat anymore
        OneMessage.sharedInstance.isFriendFromOpenChat = nil
        
        // Info: Make sure that the chatlist is up to date
        NotificationCenter.default.post(name: .reorderChatListVC, object: nil)
        
       
        
    }
    
    @objc func refreshChatMessagesAfterDeletion(notification: Notification) {
        // jid obtained from ChatViewVC
        let fromJid = (recipientXMPP?.jidStr)! + "/chat.krownunity.com"
        // jid obtained from ChatViewVC
        let toJid = currentSender().senderId
        // convert notification object to XMPPMessage
        let message = notification.object as! XMPPMessage
        // get jid of the user that received the message, obtained from the retract message
        let sentTo = message.attribute(forName: "to")?.stringValue
        // check again if this is retract message
        if let retractedMessage = message.attribute(forName: "id")?.stringValue {
            if retractedMessage == "retract-message-1" {
                let sentFrom = (message.attribute(forName: "from")?.stringValue)!
                let applyToArray = message.elements(forName: "apply-to")
                let applyTo = applyToArray[0]
                let messageID = applyTo.attribute(forName: "id")?.stringValue
                // check if sender's and receiver's jid from ChatViewVC correspond to jids from the message
                if fromJid == sentFrom && toJid == sentTo! {
                    // delete the message with a particular messageID
                    OneMessage.sharedInstance.deleteMessagesBasedOnIDFrom(jid: sentFrom, messageID: messageID!)
                    // if the image was previously deleted, delete the corresponding key-value pair
                    if self.photosLocalIdentifiers[messageID!] != nil {
                        self.deleteKeyValueFromLocalIdentifiers(messageIdString: messageID!)
                    }
                    // find the message object index in order to delete it from the local array
                    if let index = messageList.firstIndex(where: {$0.messageId == messageID!}) {
                        messageList.remove(at: index)
                        messagesCollectionView.reloadData()
                    }
                }
            }
        }
    }
    func callsForMAtchUsers()
    {
        if(isFromMatchVC)
        {
            if(selectedMessageTypeFromMatch == .text)
            {
                sendMessageFromMatchView()
            }
            else if(selectedMessageTypeFromMatch == .image)
            {
                send(image: imageMessage!)
            }
            else if(selectedMessageTypeFromMatch == .location) {
                sendUserLocationForMatchView()
            }
            else if(selectedMessageTypeFromMatch == .paperClip)
            {
                didPressAattechmentBtn()
            }
            isFromMatchVC = false
            
        }
    }
    func goBackToController()
    {
        self.navigationController?.popPushToVC(ofKind: UIViewController.self, pushController: HomeVC())
        self.dismiss(animated: true)
    }
    @objc func backBtn() {
        let jidString = "krownuser_\(matchObject.id)@" + URLHandler.xmpp_domain
        let name = matchObject.name
        OneChats.addUserToChatList(jidStr: jidString, displayName: name)

        // first read the dictionary from UserDefaults that holds the data
        var unreadMessages = UserDefaults.standard.object(forKey: "unreadMessages") as? [String: Int] ?? [String: Int]()
        // reset the number of unread messages and save
        if unreadMessages[jidString] != nil {
            unreadMessages.updateValue(0, forKey: (jidString))
            UserDefaults.standard.set(unreadMessages, forKey: "unreadMessages")

        }
        goBackToController()
        
        //TODO: - Changed below for back handling
        //----To make as previous one uncomment below
       /* let transition = CATransition()
        transition.duration = 0.25
        transition.type = CATransitionType.push
        transition.subtype = CATransitionSubtype.fromLeft
        self.view.window!.layer.add(transition, forKey: kCATransition)
        self.navigationController?.popViewController(animated: true)*/
        
        
    }
    

    @objc func flagBtn() {
        
        let alertController = UIAlertController()
        alertController.view.subviews.first?.subviews.first?.subviews.first?.backgroundColor = UIColor.white
        
        let unmatchBtn = UIAlertAction(title: "Unmatch", style: .default, handler: { (_) -> Void in
            //print("Unmatch button tapped")
            self.unmatchAPI()
        })
        unmatchBtn.setValue(UIColor.slateGrey, forKey: "titleTextColor")
        let  reportBtn = UIAlertAction(title: "Unmatch & Report", style: .default, handler: { (_) -> Void in
            //print("Unmatch & report button tapped")
            let message = "User \(String(describing: UserDefaults.standard.string(forKey: WebKeyhandler.User.userID)!) ) has flagged user \(self.personObject.id) for having a targeting post"
           // self.flagUserEmail(message: message)
            self.unmatchReportAPI()
        })
        
        reportBtn.setValue(UIColor.slateGrey, forKey: "titleTextColor")
        let cancelButton = UIAlertAction(title: "Cancel", style: .cancel, handler: { (_) -> Void in
            //print("Cancel button tapped")
        })
        cancelButton.setValue(UIColor.slateGrey, forKey: "titleTextColor")
        alertController.addAction(unmatchBtn)
        alertController.addAction(reportBtn)
        alertController.addAction(cancelButton)
        
        // self.navigationController!.present(alertController, animated: true, completion: nil)
        alertController.popoverPresentationController?.sourceView = self.view // works for both iPhone & iPad
        
        present(alertController, animated: true) {
            //print("option menu presented")
        }
        
        /*   self.present(alertController, animated: true, completion: {
         print("completion block")
         })*/
    }
    func flagUserEmail(message: String) {
        let mainController = MainController()
        mainController.sendEmail(to: personObject.id, message: message) { (_) in
            
        }
    }
    func unmatchReportAPI() {
        // like in database
        let main = mainController
        let thisUserID: String = UserDefaults.standard.object(forKey: WebKeyhandler.User.userID) as! String
        let swipeCardID : String = matchObject.id
        main.swipeAction(thisUserID, action: 4, swipeCardID: swipeCardID) { (response) in
            
            if (response["ErrorCode"]! as! String) == "47" || (response["ErrorCode"]! as! String) == "InviteAction done"{
                self.flagUserProfileEmail(message: "Chat")
                
            }
        }
    }
    func unmatchAPI() {
        // like in database
        let main = mainController
        let thisUserID: String = UserDefaults.standard.object(forKey: WebKeyhandler.User.userID) as! String
        let swipeCardID : String = matchObject.id
        main.swipeAction(thisUserID, action: 4, swipeCardID: swipeCardID) { (response) in
            
            if (response["ErrorCode"]! as! String) == "47" || (response["ErrorCode"]! as! String) == "InviteAction done"{
                self.customView()
                self.label.text = "Blocked"
                let when = DispatchTime.now() + 2.5
                DispatchQueue.main.asyncAfter(deadline: when){
                    let transition = CATransition()
                    transition.duration = 0.25
                    transition.type = CATransitionType.push
                    transition.subtype = CATransitionSubtype.fromLeft
                    self.view.window!.layer.add(transition, forKey: kCATransition)
                    self.navigationController?.popViewController(animated: true)
                }
            }
        }
    }
    func flagUserProfileEmail(message: String) {
        let mainController = MainController()
        mainController.sendUserProfileEmail(to: matchObject.id, message: message, report_type: "Chat Reporting") { (_) in
            self.customView()
            self.label.text = "Blocked & Reported"
            let when = DispatchTime.now() + 2.5
            DispatchQueue.main.asyncAfter(deadline: when){
                let transition = CATransition()
                transition.duration = 0.25
                transition.type = CATransitionType.push
                transition.subtype = CATransitionSubtype.fromLeft
                self.view.window!.layer.add(transition, forKey: kCATransition)
                self.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    public func oneStream(sender: XMPPStream, composingUser: XMPPUserCoreDataStorageObject, userIsComposing: Bool) {
        self.isTyping = userIsComposing
        
        if !isTyping {
            
            // messageInputBar.topStackView.arrangedSubviews.first?.removeFromSuperview()
            // messageInputBar.topStackViewPadding = .zero
            
        } else {
            
            let label = UILabel()
            label.text = "\(matchObject.name) is typing..."
            label.font = MainFont.heavy.withUI(size: 16)
            // messageInputBar.topStackView.addArrangedSubview(label)
            
            // messageInputBar.topStackViewPadding.top = 6
            // messageInputBar.topStackViewPadding.left = 12
            
            // The backgroundView doesn't include the topStackView. This is so things in the topStackView can have transparent backgrounds if you need it that way or another color all together
            // messageInputBar.backgroundColor = messageInputBar.backgroundView.backgroundColor
            
        }
    }
    
    public func oneStream(sender: XMPPStream, didReceiveMessage message: XMPPMessage, from user: XMPPUserCoreDataStorageObject, ofType type: String) {
        
        // TODO: Test whether open chat is the one which is supposed to receive and whether the it is a message
        if recipientXMPP?.jidStr == user.jidStr {
            
            // check if it is a "regular" message containg body
            if message.isMessageWithBody {
                // BUG: The message.type() is not correct
                let messageObject = OneMessage.generateMessage(messageText: message.body!, messageID: message.attributeStringValue(forName: "id")!, messageString: "", senderId: (recipientXMPP?.jidStr)!, senderDisplayName: "", date: Date(), type: message.elements(forName: "customFields")[0].attributeStringValue(forName: "type")!)
                
                // Add it to the view & list
                messageList.append(messageObject)
                messagesCollectionView.insertSections([messageList.count - 1])
                messagesCollectionView.scrollToLastItem()
                addOrRemoveEncouragementView()
            }
            
            // check if retract message exists, delete it locally for the recepient
            if let retractedMessage = message.attribute(forName: "id")?.stringValue {
                if retractedMessage == "retract-message-1" {
                    let from = message.attribute(forName: "from")?.stringValue
                    let applyToArray = message.elements(forName: "apply-to")
                    let applyTo = applyToArray[0]
                    let messageID = applyTo.attribute(forName: "id")?.stringValue
                    OneMessage.sharedInstance.deleteMessagesBasedOnIDFrom(jid: from!, messageID: messageID!)
                    // if the image was previously deleted, delete the corresponding key-value pair
                    if self.photosLocalIdentifiers[messageID!] != nil {
                        self.deleteKeyValueFromLocalIdentifiers(messageIdString: messageID!)
                    }
                    // find the message object index in order to delete it from the local array
                    if let index = messageList.firstIndex(where: {$0.messageId == messageID!}) {
                        messageList.remove(at: index)
                        messagesCollectionView.reloadData()
                    }
                }
            }
        }
    }
    
    func addOrRemoveEncouragementView() {
        
        // Todo: Find a better way to control when the encouragement view is visible
        if messageList.count == 0 {
            bottomView.txtChat.placeholder = "Introduce yourself..."
            encouragementView.isHidden = false
            encouragementView.removeFromSuperview()
            setupNoMessagesEncouragementView()
        } else {
            bottomView.txtChat.placeholder = ""
            encouragementView.isHidden = true
            encouragementView.removeFromSuperview()
        }
    }
    func setupNoMessagesEncouragementView() {
        
        // Set up of the different views needed
        let encouragementFrame = CGRect.init(x: 0, y: 0, width: 300, height: 250)
        encouragementView = UIView(frame: encouragementFrame)
        
//        let nameLabelFrame = CGRect.init(x: 10, y: 10, width: 180, height: 60)
//        let nameLabelView = UILabel(frame: nameLabelFrame)
//        nameLabelView.textAlignment = NSTextAlignment.center
//        nameLabelView.textColor = UIColor.slateGrey
//        nameLabelView.numberOfLines = 2
//        encouragementView.addSubview(nameLabelView)
//
//        let timeAgoLabelFrame = CGRect.init(x: 10, y: 30, width: 180, height: 30)
//        let timeAgoLabelView = UILabel(frame: timeAgoLabelFrame)
//        timeAgoLabelView.textAlignment = NSTextAlignment.center
//        timeAgoLabelView.textColor = UIColor.slateGrey
//        timeAgoLabelView.font = UIFont.systemFont(ofSize: 18)
//        encouragementView.addSubview(timeAgoLabelView)
        
        let userPictureFrame = CGRect.init(x: 75, y: 0, width: 150, height: 150)
        userPictureView = UIImageView(frame: userPictureFrame)
        userPictureView.layer.cornerRadius = 75
        userPictureView.layer.masksToBounds = true
        userPictureView.contentMode = UIView.ContentMode.scaleAspectFill
        encouragementView.addSubview(userPictureView)
        
//        let userPictureBorderFrame = CGRect(x: 45, y: 80, width: 100, height: 100)
//        let userPictureBorderView = UIImageView(frame: userPictureBorderFrame)
//        userPictureBorderView.image = UIImage(named: "ProfilePicturePlaceholder")
//        encouragementView.addSubview(userPictureBorderView)
        
        let encouragementLabelFrame = CGRect(x: 40, y: 160, width: 220, height: 80)
        let encouragementLabelView = UILabel(frame: encouragementLabelFrame)
        encouragementLabelView.numberOfLines = 2
        encouragementLabelView.textAlignment = NSTextAlignment.center
        encouragementLabelView.textColor = UIColor.slateGrey
        encouragementLabelView.font = UIFont(name: "Avenir-Medium", size: 24)
        encouragementView.addSubview(encouragementLabelView)
        
//        let userPictureButton = UIButton(type: UIButton.ButtonType.custom)
//        userPictureButton.frame = CGRect(x: 45, y: 80, width: 100, height: 100)
//        userPictureButton.addTarget(self, action: #selector(headerTitleViewTapped), for: UIControl.Event.touchUpInside)
//        encouragementView.addSubview(userPictureButton)
        
        encouragementView.center = self.view.center
        self.view.insertSubview(encouragementView, at: 2
        )
        
        // Customization of the different views
        let encouragementStringArray: NSArray = [
            "You only live once!",
            "You can do it!",
            "What if you don't do something?",
            "What do you have to lose?",
            "It's your turn!",
            "Don't hold back!",
            "What if you were meant to be?"]
        let encouragementStringCount = UInt32(encouragementStringArray.count)
        let randomNumberInEncouragemens = arc4random_uniform(encouragementStringCount)
        let encouragementString = encouragementStringArray.object(at: Int(randomNumberInEncouragemens)) as! String
        encouragementLabelView.text = encouragementString
        
//        let nameLabelString = "You matched with \(matchObject.name)"
//        nameLabelView.text = nameLabelString
        
        var path = ""
        if let resourcePath = Bundle.main.resourcePath {
            let imgName = "man.jpg"
            path = resourcePath + "/" + imgName
        }
        var imageUrl = URL(fileURLWithPath: path)
        
        if matchObject.imageArray.count > 0 {
            if matchObject.imageArray[0].count > 0 {
                imageUrl = URL(string: matchObject.imageArray[0])!
                if imageUrl.pathExtension.lowercased() == WebKeyhandler.imageHandling.mp4 {
                    
                    looperImage = PlayerLooper(videoURL: imageUrl, loopCount: -1)
                    
                } else {
                    //Add authentication header
                    var imageUrlRequest = URLRequest(url: imageUrl)
                    var headers: HTTPHeaders
                    if UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token) != nil {
                        headers = [.authorization(bearerToken: UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token)! as! String)]
                    } else {
                        headers = [.authorization(bearerToken: "ForceRefresh"),]
                    }
                    imageUrlRequest.headers = headers
                    
                    let placeholderImage = UIImage(named: "man.jpg")!
        //            MBProgressHUD.showAdded(to: userPictureView, animated: true)
                    userPictureView.af.setImage(
                        withURLRequest: imageUrlRequest,
                        placeholderImage: placeholderImage,
                        imageTransition: .crossDissolve(0.2), completion: { (_) in
        //                    MBProgressHUD.hide(for: self.userPictureView, animated: true)
                            self.getBothUserImage()
                        })
                }
            } else {
                userPictureView.image = UIImage(named: "man.jpg")!
            }
        }
        
    }
    
    func setUpCustomNavBar() {
        
        // Creates the full view where subviews can be added
        let headerTitleFrame = CGRect.init(x: 0, y: 0, width: 200, height: 44)
        let headerTitleView = UILabel.init(frame: headerTitleFrame)
        headerTitleView.backgroundColor = UIColor.clear
        headerTitleView.autoresizesSubviews = false
        
        // Makes it a button
        let titleTapButton = UIButton(type: UIButton.ButtonType.custom)
        titleTapButton.frame = CGRect.init(x: 0, y: 0, width: 200, height: 44)
        titleTapButton.addTarget(self, action: #selector(headerTitleViewTapped), for: UIControl.Event.touchUpInside)
        headerTitleView.isUserInteractionEnabled = true
        
        // Name Label
        let recipientNameFrame = CGRect.init(x: -50, y: 0, width: 300, height: 44)
        let recipientNameView = UILabel.init(frame: recipientNameFrame)
        recipientNameView.backgroundColor = UIColor.clear
        recipientNameView.font = UIFont(name: "Avenir-Heavy", size: 24)
        recipientNameView.adjustsFontSizeToFitWidth = true
        recipientNameView.minimumScaleFactor = 0.2
        recipientNameView.numberOfLines = 2
        recipientNameView.textColor = UIColor.slateGrey
        recipientNameView.textAlignment = NSTextAlignment.center
        recipientNameView.text = matchObject.name
        
        // Time Label
        let timeLabelFrame = CGRect.init(x: 0, y: 20, width: 200, height: 20)
        let timeLabelView = UILabel.init(frame: timeLabelFrame)
        timeLabelView.backgroundColor = UIColor.clear
        timeLabelView.font = UIFont.systemFont(ofSize: 12)
        timeLabelView.textAlignment = NSTextAlignment.center
        timeLabelView.textColor = UIColor.slateGrey
        timeLabelView.adjustsFontSizeToFitWidth = true
        timeLabelView.text = "Last active \(matchObject.lastActiveTime)"
        
        // Makes the navbar transparent with image background
        self.navigationController?.navigationBar.isTranslucent = true
        
        self.navigationController?.navigationBar.shadowImage = UIImage()
        
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(named: "Background standard"), for: .default)
        
        // Button for showing the profile of a user
        arrowButtonForProfile = UIButton(type: UIButton.ButtonType.custom)
        arrowButtonForProfile.setImage(UIImage(named: "blue_down_arrow"), for: UIControl.State.normal)
        arrowButtonForProfile.frame = CGRect.init(x: -50, y: 0, width: 300, height: 44)
        arrowButtonForProfile.isUserInteractionEnabled = false
        headerTitleView.addSubview(titleTapButton)
//        headerTitleView.addSubview(timeLabelView)
        headerTitleView.addSubview(recipientNameView)
//        headerTitleView.addSubview(arrowButtonForProfile)
        self.navigationItem.titleView = headerTitleView
        
    }
    
    func setupBackground() {
        // Clear the collectionview background
        messagesCollectionView.backgroundColor = UIColor.clear
        
        // screen width and height:
        let width = UIScreen.main.bounds.size.width
        let height = UIScreen.main.bounds.size.height
        
        let backgroundFrame = CGRect(x: 0, y: 0, width: width, height: height)
        let imageViewBackground = UIImageView(frame: backgroundFrame)
//        imageViewBackground.image = UIImage(named: "Background standard")
        imageViewBackground.backgroundColor = .white
        // you can change the content mode:
        imageViewBackground.contentMode = UIView.ContentMode.scaleAspectFill
        
        self.view.addSubview(imageViewBackground)
        self.view.sendSubviewToBack(imageViewBackground)
    }
    func resetStackButton()
    {
        UIView.animate(withDuration: 0.3, delay: 0.0, animations: { [self] in
            bottomView.btn_attachment.isHidden = true
            bottomView.btn_camera.isHidden = false
            bottomView.btn_camera.alpha = 1
            bottomView.btn_gallery.isHidden = false
            bottomView.btn_gallery.alpha = 1
            bottomView.btn_location.isHidden = false
            bottomView.btn_location.alpha = 1
            bottomView.btn_send.isHidden = true
        })
    }
    @objc func btn_attachment(_ sender: UIButton) {
        didPressAattechmentBtn()
    }
    @objc func btn_camera(_ sender: UIButton) {
        actionSheetResponse("camera")
    }
    @objc func btn_gallery(_ sender: UIButton) {
        actionSheetResponse("gallery")
    }
    @objc func btn_location(_ sender: UIButton) {
        actionSheetResponse(WebKeyhandler.Location.location)
    }
    @objc func btn_send(_ sender: UIButton) {
        
        if let text = bottomView.txtChat.text {
            
            let attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white])
            
            let message = MessageObject(attributedText: attributedText, sender: currentSender(), messageId: UUID().uuidString, date: Date())
            messageList.append(message)
            messagesCollectionView.insertSections([messageList.count - 1])
            
            guard let jidStr = recipientXMPP?.jidStr else{
                // neither crash nor msgs are send
                bottomView.txtChat.text = ""
                resetStackButton()
                self.messagesCollectionView.scrollToLastItem()
                return
            }
            
            OneMessage.sendMessage(message: text, to: jidStr, is: WebKeyhandler.Chat.xmppChat, completionHandler: { (_, _) -> Void in
            })
            addOrRemoveEncouragementView()
        }
        bottomView.txtChat.text = ""
        resetStackButton()
//        bottomView.frame.origin.y = y - self.keyboardHeight
//        self.messagesCollectionView.contentInset.bottom = self.keyboardHeight + 63
        self.messagesCollectionView.scrollToLastItem()
//        dismissKeyboard()
    }

    func configureInputBarAccessoryView() {
        
        let window = UIApplication.shared.windows.first
        let bottomPadding : CGFloat = window?.safeAreaInsets.bottom ?? 0
        let height : CGFloat = 63 + bottomPadding
        let width : CGFloat = window?.frame.width ?? 0
        y = (window?.frame.height ?? 0) - height
        bottomView = BottomChat(frame: CGRect(x: 0, y: y, width: width, height: height))
        bottomView.txtChat.delegate = self
//        bottomView.txtChat.addTarget(self, action: #selector(self.textFieldDidChange(_:)), for: .editingChanged)
//        bottomView.txtChat.addTarget(self, action: #selector(self.myTargetFunction(_:)), for: .touchDown)
        
        bottomView.btn_attachment.addTarget(self, action: #selector(self.btn_attachment(_:)), for: .touchUpInside)
        bottomView.btn_camera.addTarget(self, action: #selector(self.btn_camera(_:)), for: .touchUpInside)
        bottomView.btn_gallery.addTarget(self, action: #selector(self.btn_gallery(_:)), for: .touchUpInside)
        bottomView.btn_location.addTarget(self, action: #selector(self.btn_location(_:)), for: .touchUpInside)
        bottomView.btn_send.addTarget(self, action: #selector(self.btn_send(_:)), for: .touchUpInside)
        
        resetStackButton()
        if isFromSwiftUI {
            bottomView.removeFromSuperview()
            hostingController?.view.addSubview(bottomView)
            //            self.presentationController?.presentedView?.addSubview(bottomView)
//            self.rootView.view.addSubview(bottomView)
//            bottomView.bringSubviewToFront(UIApplication.shared.windows[0].rootViewController!.view)
        } else {
            self.view.addSubview(bottomView)
        }
        messageInputBar.isHidden = true
//        messageInputBar.delegate = self
//        messageInputBar.inputTextView.tintColor = UIColor.green
//        messageInputBar.sendButton.tintColor = UIColor.green
//        messageInputBar.backgroundView.backgroundColor = .white
//        messageInputBar.isTranslucent = false
//        messageInputBar.inputTextView.backgroundColor = .clear
//        messageInputBar.inputTextView.layer.borderWidth = 0
//        messageInputBar.inputTextView.textColor = .black
//        let items = [
//            makeButton(named: "clip").onTextViewDidChange { button, textView in
//                button.isEnabled = textView.text.isEmpty
//            },
//            .flexibleSpace,
//            messageInputBar.sendButton
//                .configure {
//                    $0.layer.cornerRadius = 8
//                    $0.layer.borderWidth = 1.5
//                    $0.layer.borderColor = $0.titleColor(for: .disabled)?.cgColor
//                    $0.setTitleColor(.white, for: .normal)
//                    $0.setTitleColor(.white, for: .highlighted)
//                    $0.setSize(CGSize(width: 52, height: 30), animated: true)
//                }.onDisabled {
//                    $0.layer.borderColor = $0.titleColor(for: .disabled)?.cgColor
//                    $0.backgroundColor = .white
//                }.onEnabled {
//                    $0.backgroundColor = UIColor(red: 69/255, green: 193/255, blue: 89/255, alpha: 1)
//                    $0.layer.borderColor = UIColor.clear.cgColor
//                }.onSelected {
//                    // We use a transform becuase changing the size would cause the other views to relayout
//                    $0.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
//                }.onDeselected {
//                    $0.transform = CGAffineTransform.identity
//                }
//        ]
//        items.forEach { $0.tintColor = .royalPurple }
//
//        // We can change the container insets if we want
//        messageInputBar.inputTextView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
//        messageInputBar.inputTextView.placeholderLabelInsets = UIEdgeInsets(top: 8, left: 5, bottom: 8, right: 5)
//
//        // Since we moved the send button to the bottom stack lets set the right stack width to 0
//        messageInputBar.setRightStackViewWidthConstant(to: 0, animated: true)
//
//        // Finally set the items
//        messageInputBar.setStackViewItems(items, forStack: .bottom, animated: true)
    }
    
    func makeButton(named: String) -> InputBarButtonItem {
        return InputBarButtonItem()
            .configure {
                $0.spacing = .fixed(10)
                $0.image = UIImage(named: named)?.withRenderingMode(.alwaysTemplate)
                $0.setSize(CGSize(width: 30, height: 30), animated: true)
            }.onSelected {
                $0.tintColor = UIColor.royalPurple
            }.onDeselected {
                $0.tintColor = UIColor.royalPurple
            }.onTouchUpInside { _ in
                self.didPressAattechmentBtn()
            }
    }
    func getBothUserImage() {
        if matchObject.imageArray.count > 0 {
            var headers: HTTPHeaders
            if UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token) != nil {
                headers = [.authorization(bearerToken: UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token)! as! String)]
            } else {
                headers = [.authorization(bearerToken: "ForceRefresh"),]
            }
            AF.request(matchObject.imageArray[0], method: .get, headers: headers).responseImage { response in
                if case .success(let image) = response.result {
                    self.imgOtherUser = image
                    self.messagesCollectionView.reloadData()
                }
            }
        }
    }
    func setupKolodaView() {
        
        self.view.addSubview(kolodaView)
        self.view.bringSubviewToFront(kolodaView)
        
        kolodaView.isHidden = true
    }
    
    @objc func headerTitleViewTapped() {
        mainController.getProfile(userID: matchObject.id, callback: { (match) in
            self.personObject = match
            let storyboard = UIStoryboard(name: "Chat", bundle: nil)
            guard let swipeCardPreview = storyboard.instantiateViewController(
                    identifier: "SwipeCardPreview") as? SwipeCardPreview else {
                fatalError("Cannot load from storyboard")
            }
            swipeCardPreview.personObject = self.personObject
            self.navigationController?.pushViewController(swipeCardPreview, animated: true)
        })

//        if !arrowButtonForProfile.isSelected {
//            arrowButtonForProfile.setImage(UIImage(named: "blue_up_arrow"), for: UIControl.State.normal)
//            arrowButtonForProfile.isSelected = true
//            // Present the profile of a user
//            mainController.getProfile(fbID: matchObject.id, callback: { (match) in
//                self.personObject = match
//                self.kolodaViewNumberOfCards = 1
//                self.kolodaView.resetCurrentCardIndex()
//                self.kolodaView.isHidden = false
//                // self.messageInputBar.isHidden = true
//                // self.messageInputBar.inputTextView.resignFirstResponder() //Hides keyboard
//            })
//            
//        } else {
//            // Hide the profile of user
//            arrowButtonForProfile.isSelected = false
//            arrowButtonForProfile.setImage(UIImage(named: "blue_down_arrow"), for: UIControl.State.normal)
//            kolodaViewNumberOfCards = 0
//            kolodaView.resetCurrentCardIndex()
//            kolodaView.isHidden = true
//            // messageInputBar.isHidden = false
//        }
    }
    
    @objc func loadMoreMessages() {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: DispatchTime.now()) {
            self.getMessages(count: 10) { messages in
                DispatchQueue.main.async {
                    self.messageList.insert(contentsOf: messages, at: 0)
                    self.messagesCollectionView.reloadDataAndKeepOffset()
                    self.refreshControl.endRefreshing()
                }
            }
        }
    }
    
    func getMessages(count: Int, completion: ([MessageObject]) -> Void) {
        var messages: [MessageObject] = []
        var safeCount = count
        if count>messageListHistory.count-1 {
            safeCount = messageListHistory.count
        }
        // Append messages
        for i in 0..<safeCount {
            let message = messageListHistory[safeCount-1-i]
            
            messages.append(message)
        }
        // Remove messages for next to be loaded.
        messageListHistory.removeSubrange(0..<safeCount)
        
        completion(messages)
    }
    
}
//MARK: - Send Message from match view methods
extension MatchesChatViewVC
{
    func sendMessageFromMatchView()
    {
        sendChatMessage()
    }
    func sendChatMessage()
    {
        if strMessageFromMatchVC.count != 0 {
            
            let attributedText = NSAttributedString(string: strMessageFromMatchVC, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white])
            
            let message = MessageObject(attributedText: attributedText, sender: currentSender(), messageId: UUID().uuidString, date: Date())
            messageList.append(message)
            messagesCollectionView.insertSections([messageList.count - 1])
            
            OneMessage.sendMessage(message: strMessageFromMatchVC, to: (recipientXMPP!.jidStr)!, is: WebKeyhandler.Chat.xmppChat, completionHandler: { (_, _) -> Void in
            })
            addOrRemoveEncouragementView()
        }
        bottomView.txtChat.text = ""
        resetStackButton()
//        bottomView.frame.origin.y = y - self.keyboardHeight
        self.messagesCollectionView.contentInset.bottom = self.keyboardHeight + 63
        self.messagesCollectionView.scrollToLastItem()
    }
    func sendUserLocationForMatchView()
    {
        let latestlocation = UserDefaults.standard.dictionary(forKey: WebKeyhandler.Location.location)

        let latitude: Double = latestlocation![WebKeyhandler.Location.currentLat] as! Double
        let longitude: Double = latestlocation![WebKeyhandler.Location.currentLong] as! Double
        let locationCoordinates = CLLocation.init(latitude: CLLocationDegrees.init(latitude), longitude: CLLocationDegrees.init(longitude))

        let locationMessage = MessageObject(location: locationCoordinates, sender: self.currentSender(), messageId: UUID().uuidString, date: Date())

        self.messageList.append(locationMessage)
        self.messagesCollectionView.insertSections([self.messageList.count - 1])
        self.messagesCollectionView.scrollToLastItem(animated: true)
        self.addOrRemoveEncouragementView()

        var messageWithCoordinates = String()
        messageWithCoordinates = String("\(latitude) \(longitude)")
        // Send message
            OneMessage.sendMessage(message: messageWithCoordinates, to: (self.recipientXMPP?.jidStr)!, is: WebKeyhandler.Chat.xmppLocation, completionHandler: { (_, _) -> Void in
            })
    }
}

// MARK: - MessagesDataSource

extension MatchesChatViewVC: MessagesDataSource {
    func currentSender() -> SenderType {
        let userID = UserDefaults.standard.string(forKey: WebKeyhandler.User.userID)!
        let myFirstName = UserDefaults.standard.string(forKey: WebKeyhandler.User.firstName)!
        
        let myJid = URLHandler.userPreFix + userID + "@" + URLHandler.xmpp_domain
        return ChatUserObject(senderId: myJid, displayName: myFirstName)
    }
    
    func numberOfSections(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messageList.count
    }
    
    func numberOfMessages(in messagesCollectionView: MessagesCollectionView) -> Int {
        return messageList.count
    }
    
    func messageForItem(at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageType {
        return messageList[indexPath.section]
    }
    func messageTopLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        let name =  message.sender.displayName
        return NSAttributedString(string: name, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption1), NSAttributedString.Key.foregroundColor: Color.lightGray])
    }
    
    func messageBottomLabelAttributedText(for message: MessageType, at indexPath: IndexPath) -> NSAttributedString? {
        // BUG: The indexpath.item always returns 0
        struct ConversationDateFormatter {
            static let formatter: DateFormatter = {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-dd-MM HH:mm"
                return formatter
            }()
        }
        
        if self.messageList.indices.contains(indexPath.item+1) {
            let tenMinutes: TimeInterval = 60*10
            let lastMessageTime = self.messageList[indexPath.item+1].sentDate.addingTimeInterval(tenMinutes)
            let messageTime = self.messageList[indexPath.item].sentDate
            
            if lastMessageTime < messageTime {
                let formatter = ConversationDateFormatter.formatter
                let dateString = formatter.string(from: message.sentDate)
                return NSAttributedString(string: dateString, attributes: [NSAttributedString.Key.font: UIFont.preferredFont(forTextStyle: .caption2), NSAttributedString.Key.foregroundColor: Color.lightGray])
                
            }
            
        }
        return nil
    }
}

// MARK: - MessagesDisplayDelegate

extension MatchesChatViewVC: MessagesDisplayDelegate {
    
    // MARK: - Text Messages
    
    func textColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .pinkMoment : .slateGrey
    }
    
    func detectorAttributes(for detector: DetectorType, and message: MessageType, at indexPath: IndexPath) -> [NSAttributedString.Key: Any] {
        return MessageLabel.defaultAttributes
    }
    
    func enabledDetectors(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> [DetectorType] {
        return [.url]
    }
    
    // MARK: - All Messages
    
    func backgroundColor(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> UIColor {
        return isFromCurrentSender(message: message) ? .royalPurple : UIColor(red: 230/255, green: 230/255, blue: 230/255, alpha: 1)
    }
    
    func messageStyle(for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> MessageStyle {
        let corner: MessageStyle.TailCorner = isFromCurrentSender(message: message) ? .bottomRight : .bottomLeft
        return .bubbleTail(corner, .curved)
    }
    
    func configureAvatarView(_ avatarView: AvatarView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        
        var avatar = Avatar()
        // Is the sender myself?
        if matchObject.id != message.sender.senderId.slice(from: "_", to: "@") {
            
            let myFirstName = UserDefaults.standard.string(forKey: WebKeyhandler.User.firstName)!
            avatar = Avatar(image: imgYouUser, initials: String(describing: myFirstName[myFirstName.startIndex]))

        } else {
            
            let myMatchFirstName = matchObject.name
            avatar = Avatar(image: imgOtherUser, initials: String(describing: myMatchFirstName[myMatchFirstName.startIndex]))
        }
        avatarView.set(avatar: avatar)
    }
    
    // MARK: - Location Messages
    
    func annotationViewForLocation(message: MessageType, at indexPath: IndexPath, in messageCollectionView: MessagesCollectionView) -> MKAnnotationView? {
        let annotationView = MKAnnotationView(annotation: nil, reuseIdentifier: nil)
        let pinImage = #imageLiteral(resourceName: "pin")
        annotationView.image = pinImage
        annotationView.centerOffset = CGPoint(x: 0, y: -pinImage.size.height / 2)
        return annotationView
    }
    
    func animationBlockForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> ((UIImageView) -> Void)? {
        return { view in
            view.layer.transform = CATransform3DMakeScale(0, 0, 0)
            view.alpha = 0.0
            UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [], animations: {
                view.layer.transform = CATransform3DIdentity
                view.alpha = 1.0
            }, completion: nil)
        }
    }
    
    func snapshotOptionsForLocation(message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) -> LocationMessageSnapshotOptions {
        
        return LocationMessageSnapshotOptions()
    }
    
    func configureMediaMessageImageView(_ imageView: UIImageView, for message: MessageType, at indexPath: IndexPath, in messagesCollectionView: MessagesCollectionView) {
        // TODO: Set up async image loading
        switch message.kind {
        case .photo(let messageMediaItem):
            if let msgMediaItem = messageMediaItem as? MessageMediaItem {
                let url = msgMediaItem.url
                //Add authentication header
                var imageUrlRequest = URLRequest(url: url!)
                var headers: HTTPHeaders
                if UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token) != nil {
                    headers = [.authorization(bearerToken: UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token)! as! String)]
                } else {
                    headers = [.authorization(bearerToken: "ForceRefresh"),]
                }
                imageUrlRequest.headers = headers
                
                imageView.af.setImage(withURLRequest: imageUrlRequest)
            }
            
        case .text, .attributedText, .location, .video, .emoji, .contact, .audio, .linkPreview(_), .custom(_):
            break
        }
    }
    
}

// MARK: - MessagesLayoutDelegate

extension MatchesChatViewVC: MessagesLayoutDelegate {
    
}

// MARK: - MessageCellDelegate

extension MatchesChatViewVC: MessageCellDelegate {
    
    func didTapAvatar(in cell: MessageCollectionViewCell) {
        //print("Avatar tapped")
    }
    
    func didTapImage(in cell: MessageCollectionViewCell) {
        //print("Image tapped")
        let message = messageForItem(at: messagesCollectionView.indexPath(for: cell)!, in: messagesCollectionView)
        
        self.selectedIndexPath = messagesCollectionView.indexPath(for: cell)!
        
        switch message.kind {
        case .photo(let messageMediaItem):
            if let msgMediaItem = messageMediaItem as? MessageMediaItem {
                
                var image = UIImage()
                
                // if remote image exists then show it
                // else retrieve local image
                if msgMediaItem.url?.absoluteString != URLHandler.imageUploadDomain {
                    var headers: HTTPHeaders
                    if UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token) != nil {
                        headers = [.authorization(bearerToken: UserDefaults.standard.object(forKey: WebKeyhandler.User.app_auth_token)! as! String)]
                    } else {
                        headers = [.authorization(bearerToken: "ForceRefresh"),]
                    }
                    MBProgressHUD.showAdded(to: self.view, animated: true)
                    AF.request(msgMediaItem.url!, method: .get, headers: headers).responseImage { response in
                        MBProgressHUD.hide(for: self.view, animated: true)
                        if case .success(let image) = response.result {
                            self.agrumeSetup(image: image, background: .colored(.black), overlayView: self.overlayView, chatImageLocalID: self.photosLocalIdentifiers[self.messageList[self.selectedIndexPath.section].messageId] ?? "aa")
                        }
                    }
                } else {
                    image = messageMediaItem.image!
                    self.agrumeSetup(image: image, background: .colored(.black), overlayView: self.overlayView, chatImageLocalID: self.photosLocalIdentifiers[self.messageList[self.selectedIndexPath.section].messageId] ?? "aa")
                }
            }
        default:
            //print("Not a photo")
            break
        }
    }
    
    func didTapCellTopLabel(in cell: MessageCollectionViewCell) {
        //print("Top cell label tapped")
    }
    
    func didTapCellBottomLabel(in cell: MessageCollectionViewCell) {
        //print("Bottom cell label tapped")
    }
    
    func didTapMessageTopLabel(in cell: MessageCollectionViewCell) {
        //print("Top message label tapped")
    }
    
    func didTapMessageBottomLabel(in cell: MessageCollectionViewCell) {
        //print("Bottom label tapped")
    }
    
    func didTapPlayButton(in cell: AudioMessageCell) {
        //print("Play button tapped")
    }
    
    func didTapMessage(in cell: MessageCollectionViewCell) {
        //print("Message tapped")
        var textLbl = String()
        let message = messageForItem(at: messagesCollectionView.indexPath(for: cell)!, in: messagesCollectionView)
        switch message.kind {
        case .text(let text):
            textLbl = text
        case .attributedText(let text):
            textLbl = text.string
        case  .emoji(let text):
            textLbl = text
        case .video:
            textLbl = "video"
        case .audio:
            textLbl = "Audio"
        case .contact:
            textLbl = "Contact"
        case .location(let coordinates):
            // Get name and location
            
            let name = ""
            /*if message.sender == self.senderId {
             name = "Your"
             } else {
             name = senderDisplayName!
             }*/
            // Open map
            let mapView = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "mapView") as! MapVC
            mapView.userName = name
            mapView.coordinates = coordinates.location
            mapView.placeName = "" // TODO: Consider to have reverse geocoding from swiftlocation to get a placemark
            mapView.modalPresentationStyle = .overFullScreen
            mapView.handlerForPopController = {
//                self.goBackToController()
                mapView.dismiss(animated: true)
            }
            present(mapView, animated: true, completion: nil)
//            self.navigationController?.pushViewController(mapView, animated: true)
            
            //print(textLbl)
            
        default:
            //print("Message did not contain text")
            textLbl = ""
        }
        
    }
}

// MARK: - MessageLabelDelegate

extension MatchesChatViewVC: MessageLabelDelegate {
    
    func didSelectAddress(_ addressComponents: [String: String]) {
        //print("Address Selected: \(addressComponents)")
    }
    
    func didSelectDate(_ date: Date) {
        //print("Date Selected: \(date)")
    }
    
    func didSelectPhoneNumber(_ phoneNumber: String) {
        //print("Phone Number Selected: \(phoneNumber)")
    }
    
    func didSelectURL(_ url: URL) {
        //print("URL Selected: \(url)")
    }
    
    func didSelectTransitInformation(_ transitInformation: [String: String]) {
        //print("TransitInformation Selected: \(transitInformation)")
    }
    
    func didSelectHashtag(_ hashtag: String) {
        //print("Hashtag selected: \(hashtag)")
    }
    
    func didSelectMention(_ mention: String) {
        //print("Mention selected: \(mention)")
    }
    
    func didSelectCustom(_ pattern: String, match: String?) {
        //print("Custom data detector patter selected: \(pattern)")
    }
    
}
//MARK: - Register Keyboard methods
extension MatchesChatViewVC
{
    
    /*func registerKeyboardEvents()
    {
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.keyboardWillHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    @objc func keyboardWillShow(notification: Notification) {
        
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            print("Keyboard show height - ",keyboardSize.height)
            keyboardHeight = keyboardSize.height
            if self.view.frame.origin.y == 0{
                self.view.frame.origin.y -= keyboardSize.height
                
            }
        }

    }

    @objc func keyboardWillHide(notification: Notification) {
        if let keyboardSize = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue {
            
            print("Keyboard hide height - ",keyboardSize.height)

            if self.view.frame.origin.y != 0 {
//                self.view.frame.origin.y += keyboardSize.height
                self.view.frame.origin.y = 0
                
            }
        }
    }*/
}
// MARK: - InputBarAccessoryViewDelegate

extension MatchesChatViewVC: InputBarAccessoryViewDelegate {
    
    func inputBar(_ inputBar: InputBarAccessoryView, didPressSendButtonWith text: String) {
        // Each NSTextAttachment that contains an image will count as one empty character in the text: String
        
        for component in inputBar.inputTextView.components {
            
            if let image = component as? UIImage {
                
                let imageMessage = MessageObject(image: image, sender: currentSender(), messageId: UUID().uuidString, date: Date())
                messageList.append(imageMessage)
                messagesCollectionView.insertSections([messageList.count - 1])
                
            } else if let text = component as? String {
                
                let attributedText = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 17), .foregroundColor: UIColor.white])
                
                let message = MessageObject(attributedText: attributedText, sender: currentSender(), messageId: UUID().uuidString, date: Date())
                messageList.append(message)
                messagesCollectionView.insertSections([messageList.count - 1])
                
                OneMessage.sendMessage(message: text, to: (recipientXMPP?.jidStr)!, is: WebKeyhandler.Chat.xmppChat, completionHandler: { (_, _) -> Void in
                })
                
            }
            addOrRemoveEncouragementView()
        }
        
        inputBar.inputTextView.text = String()
        messagesCollectionView.scrollToLastItem()
    }
    
    func inputBar(_ inputBar: InputBarAccessoryView, textViewTextDidChangeTo text: String) {
        
        if text.count == 0 {// If all text was deleted
            if isTyping {
                hideTypingIndicator()
            }
        } else {
            timer?.invalidate()
            if !isTyping {
                self.isTyping = true
                OneMessage.sendIsComposingMessage(recipient: (recipientXMPP?.jidStr)!, completionHandler: { (_, _) -> Void in
                    self.timer = Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(MatchesChatViewVC.hideTypingIndicator), userInfo: nil, repeats: false)
                })
            } else {
                self.timer = Timer.scheduledTimer(timeInterval: 4.0, target: self, selector: #selector(MatchesChatViewVC.hideTypingIndicator), userInfo: nil, repeats: false)
            }
        }
    }
    
    @objc func hideTypingIndicator() {
        self.isTyping = false
        OneMessage.sendIsNotComposingMessage(recipient: (recipientXMPP?.jidStr)!, completionHandler: { (_, _) -> Void in
        })
    }
    func didPressAattechmentBtn() {
        let storyboard = UIStoryboard(name: "Chat", bundle: nil)
        guard let customAlertVC = storyboard.instantiateViewController(
            identifier: "CustomAlertVC") as? CustomAlertVC else {
                fatalError("Cannot load from storyboard")
            }
        customAlertVC.modalPresentationStyle = .custom
        customAlertVC.transitioningDelegate = customAlertVC
        customAlertVC.matchesChatViewVC = self
        customAlertVC.strImgArr = [["value":UIImage(named: "photo_camera")!,"action":"camera"],
                                   ["value":UIImage(named: "photo_library")!,"action":"gallery"],
                                   ["value":UIImage(named: "place")!,"action":WebKeyhandler.Location.location],
                                   ["value":"Cancel","action":"cancel"]]
        self.present(customAlertVC, animated: true, completion: nil)
    }
    func actionSheetResponse(_ sender: String) {
        switch sender {
        case "camera":
            if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.camera) {
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = self
                imagePicker.sourceType = UIImagePickerController.SourceType.camera
                imagePicker.allowsEditing = false
                imagePicker.modalPresentationStyle = .overFullScreen
                self.present(imagePicker, animated: true, completion: nil)
            }
        case "gallery":
            let imagePicker = UIImagePickerController()
            if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.savedPhotosAlbum) {
                imagePicker.modalPresentationStyle = .overFullScreen
                imagePicker.delegate = self
                imagePicker.sourceType = UIImagePickerController.SourceType.savedPhotosAlbum
                imagePicker.allowsEditing = false
                self.present(imagePicker, animated: true, completion: nil)
            }
        case WebKeyhandler.Location.location:
            let latestlocation = UserDefaults.standard.dictionary(forKey: WebKeyhandler.Location.location)

            let latitude: Double = latestlocation![WebKeyhandler.Location.currentLat] as! Double
            let longitude: Double = latestlocation![WebKeyhandler.Location.currentLong] as! Double
            let locationCoordinates = CLLocation.init(latitude: CLLocationDegrees.init(latitude), longitude: CLLocationDegrees.init(longitude))

            let locationMessage = MessageObject(location: locationCoordinates, sender: self.currentSender(), messageId: UUID().uuidString, date: Date())

            self.messageList.append(locationMessage)
            self.messagesCollectionView.insertSections([self.messageList.count - 1])
            self.messagesCollectionView.scrollToLastItem(animated: true)
            self.addOrRemoveEncouragementView()

            var messageWithCoordinates = String()
            messageWithCoordinates = String("\(latitude) \(longitude)")
            // Send message
                OneMessage.sendMessage(message: messageWithCoordinates, to: (self.recipientXMPP?.jidStr)!, is: WebKeyhandler.Chat.xmppLocation, completionHandler: { (_, _) -> Void in
                })
        case "Unmatch":
            //print("Unmatch")
            break
        case "Unmatch&Report":
            //print("Unmatch&Report")
            break
        default:
            // Last Message
            //print("Cancel")
            break
        }
    }

    func didPressAccessoryBtn() {
        // messageInputBar.inputTextView.resignFirstResponder()
        
        let sheet = UIAlertController(title: "Media messages", message: nil, preferredStyle: .actionSheet)
        
        let choosePhotoAction = UIAlertAction(title: "Pick photo", style: .default) { (_) in
            /**
             *  Choose photo from library
             */
            let imagePicker = UIImagePickerController()
            if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.savedPhotosAlbum) {
                
                imagePicker.delegate = self
                imagePicker.sourceType = UIImagePickerController.SourceType.savedPhotosAlbum
                imagePicker.allowsEditing = false
                self.present(imagePicker, animated: true, completion: nil)
            }
        }
        
        let takePhotoAction = UIAlertAction(title: "Take photo", style: .default) { (_) in
            /**
             *  Take photo from camera
             */
            
            if UIImagePickerController.isSourceTypeAvailable(UIImagePickerController.SourceType.camera) {
                let imagePicker = UIImagePickerController()
                imagePicker.delegate = self
                imagePicker.sourceType = UIImagePickerController.SourceType.camera
                imagePicker.allowsEditing = false
                self.present(imagePicker, animated: true, completion: nil)
            }
        }
        
        let locationAction = UIAlertAction(title: "Send current location", style: .default) { (_) in
            /**
             *  Add location
             */
            let latestlocation = UserDefaults.standard.dictionary(forKey: WebKeyhandler.Location.location)
            
            let latitude: Double = latestlocation![WebKeyhandler.Location.currentLat] as! Double
            let longitude: Double = latestlocation![WebKeyhandler.Location.currentLong] as! Double
            let locationCoordinates = CLLocation.init(latitude: CLLocationDegrees.init(latitude), longitude: CLLocationDegrees.init(longitude))
            
            let locationMessage = MessageObject(location: locationCoordinates, sender: self.currentSender(), messageId: UUID().uuidString, date: Date())
            
            self.messageList.append(locationMessage)
            self.messagesCollectionView.insertSections([self.messageList.count - 1])
            self.messagesCollectionView.scrollToLastItem(animated: true)
            self.addOrRemoveEncouragementView()
            
            // Refresh location
            let main = MainController()
            main.getLocation(10, forceGetLocation: true, withAccuracy: .room) { (_) in
                // Just for refreshing location
                
                // Packing a message with coordinates
                var messageWithCoordinates = String()
                messageWithCoordinates = String("\(latitude) \(longitude)")
                // Send message
                OneMessage.sendMessage(message: messageWithCoordinates, to: (self.recipientXMPP?.jidStr)!, is: WebKeyhandler.Chat.xmppLocation, completionHandler: { (_, _) -> Void in
                })
            }
            
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        sheet.addAction(choosePhotoAction)
        sheet.addAction(takePhotoAction)
        sheet.addAction(locationAction)
        //        sheet.addAction(videoAction)
        //        sheet.addAction(audioAction)
        sheet.addAction(cancelAction)
        
        self.present(sheet, animated: true, completion: nil)
    }
    
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        // Local variable inserted by Swift 4.2 migrator.
        let info = convertFromUIImagePickerControllerInfoKeyDictionary(info)
        
        let originalImage = (info[convertFromUIImagePickerControllerInfoKey(UIImagePickerController.InfoKey.originalImage)] as! UIImage)
        // can be used in future to get localIdentifier
        // let identifier = (info[UIImagePickerController.InfoKey.phAsset.rawValue] as? PHAsset)?.localIdentifier
        
        // Find size of image to set scaling
        let originalImageHeight = originalImage.size.height
        let originalImageWidth = originalImage.size.width
        var scaledImageWidth = CGFloat()
        var scaledImageHeight = CGFloat()
        if originalImageHeight  >= 1000 && originalImageHeight >= originalImageWidth { // if the size of height is more than 1000 px and picture is higher than wide
            scaledImageHeight = CGFloat(1000)
            scaledImageWidth = originalImageWidth / (originalImageHeight / scaledImageHeight) // calculates the new width of the image based on the factors from the original to the scaled image
        } else if originalImageWidth >= 1000 && originalImageWidth >= originalImageHeight { // if the size of width is more than 1000 px and picture is wider than high
            scaledImageWidth = CGFloat(1000)
            scaledImageHeight = originalImageHeight / (originalImageWidth / scaledImageWidth) // calculates the new height of the image based on the factors from the original to the scaled image
        } else {                            // If both height or width is not over 1000
            scaledImageHeight = originalImageHeight
            scaledImageWidth = originalImageWidth
        }
        
        let imageSize = CGSize.init(width: scaledImageWidth, height: scaledImageHeight)
        let scaledImage = originalImage.af.imageScaled(to: imageSize)
        send(image: scaledImage)
        dismiss(animated: true, completion: nil)
        
    }
    
    func send(image: UIImage) {
        let main = MainController() as MainController
        
        let sender = ChatUserObject(senderId: currentSender().senderId, displayName: currentSender().displayName)
        let photoMessage = MessageObject(image: image, sender: sender, messageId: messageIdInNewMessage, date: Date())
        
        main.uploadImage(image) { (dictionary) in
            if let photoUrl = dictionary["url"] {
                OneMessage.sendMessage(message: photoUrl as! String, to: (self.recipientXMPP?.jidStr)!, is: WebKeyhandler.Chat.xmppPhoto, completionHandler: { (_, completeMessage) -> Void in
                    // grab the newly cereated messageID from a new message, it will serve later to delete image message right after it has been sent using a unique messageID
                    if let tempMessageId = completeMessage.attributeStringValue(forName: "id") {
                        // retract message has "retract-message-1" as id, in that case messageId of the messageList array doesn't need to be updated. This is realy important when you delete the last image message in the chat
                        if self.messageList.count != 0 {
                            self.messageIdInNewMessage = tempMessageId
                            self.messageList[self.messageList.count-1].messageId = self.messageIdInNewMessage
                        }
                    }
                    self.messageIdInNewMessage = ""
                })
            }
        }
        
        self.messageList.append(photoMessage)
        self.messagesCollectionView.reloadData()
        self.messagesCollectionView.scrollToLastItem(animated: true)
        self.addOrRemoveEncouragementView()
    }
}

extension MatchesChatViewVC: KolodaViewDelegate {}
extension MatchesChatViewVC: KolodaViewDataSource {
    func koloda(_ koloda: KolodaView, viewForCardAt index: Int) -> UIView {
        let swipeDetailView = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "swipeDetailView") as! SwipeDetailVC
        swipeDetailView.swipeInfo = personObject
        addChild(swipeDetailView)
        swipeDetailView.view.layer.cornerRadius = 20
        swipeDetailView.dislikeButton.isHidden = true
        swipeDetailView.likeButton.isHidden = true
        swipeDetailView.waveButton.isHidden = true
        swipeDetailView.createScrollView(viewSize: kolodaView.frameForCard(at: 0))
        
        addChild(swipeDetailView)
        
        return swipeDetailView.view
    }
    
    func kolodaNumberOfCards(_ koloda: KolodaView) -> Int {
        return kolodaViewNumberOfCards
    }
    
    func kolodaSpeedThatCardShouldDrag(_ koloda: KolodaView) -> DragSpeed {
        return .fast
    }
    func kolodaDidRunOutOfCards(_ koloda: KolodaView) {
        // Hides the view so it is possible to click again on the UI Below
        kolodaView.isHidden = true
        // messageInputBar.isHidden = false
        
    }
    func koloda(_ koloda: KolodaView, didSwipeCardAt index: Int, in direction: SwipeResultDirection) {
        
        // Spins the arrow in the menu
        if arrowButtonForProfile.isSelected {
            arrowButtonForProfile.setImage(UIImage(named: "blue_down_arrow"), for: UIControl.State.normal)
            // Present the profile of a user
        } else {
            arrowButtonForProfile.setImage(UIImage(named: "blue_up_arrow"), for: UIControl.State.normal)
            // hide the profile of a user
        }
        // Stops the button from being selected and thus allowing button to switch between sides
        arrowButtonForProfile.isSelected = !arrowButtonForProfile.isSelected
        
    }
    
    // needed for getting permission to Photos
    func getPermissionIfNecessary(completionHandler: @escaping (Bool) -> Void) {
        
        guard PHPhotoLibrary.authorizationStatus() != .authorized else {
            completionHandler(true)
            return
        }
        
        PHPhotoLibrary.requestAuthorization { status in
            completionHandler(status == .authorized ? true : false)
        }
    }
    
}

// Agrue overlay delegate
extension MatchesChatViewVC: OverlayViewDelegate {
    
    func overlayView(_ overlayView: AgrumeCustomOverlayView, didSelectAction action: String) {
        
        switch action {
        case "share":
            
            let items = [self.overlayView.image]
            let ac = UIActivityViewController(activityItems: items, applicationActivities: nil)
            // get the top most controller and then show UIActivityViewController
            self.getTopMostViewController()?.present(ac, animated: true, completion: nil)
            
        case "save":
            //print("save")
            
            getPermissionIfNecessary { granted in
                guard granted else { return }
                
                PHPhotoLibrary.shared().performChanges { [self] in
                    // Create a change request from the asset to be modified.
                    let request = PHAssetChangeRequest.creationRequestForAsset(from: self.overlayView.image)
                    self.chatImageLocalID = request.placeholderForCreatedAsset!.localIdentifier
                    
                } completionHandler: { success, error in
                    //print("Finished updating asset. " + (success ? "Success." : error!.localizedDescription))
                    
                    if success {
                        let fetchOptions = PHFetchOptions()
                        self.allPhotos = PHAsset.fetchAssets(withLocalIdentifiers: [self.chatImageLocalID], options: fetchOptions)
                        if self.allPhotos.count > 0 {
                            //print("Success!")
                            
                            self.saveLocalIdentifiersInUserDefaults(messageIdString: self.messageList[self.selectedIndexPath.section].messageId, localIdentifier: self.allPhotos.lastObject!.localIdentifier)
                            
                            DispatchQueue.main.async {
                                let saveButtonDisabled = self.getButtonFromAgrumeToolbar(overlayView: overlayView, tag: 1234)
                                saveButtonDisabled.isEnabled = false
                                saveButtonDisabled.title = "Saved"
                            }
                        } else {
                            //print("Fail!")
                            //print(self.allPhotos)
                        }
                    }
                }
            }
            
        case "delete":
            //print("delete")
            
            let jid = (self.recipientXMPP?.jidStr)!
            
            // check my Jid and the if I'm the sender I can delete image for everyone
            let myJid = currentSender().senderId
            let senderJid = self.messageList[self.selectedIndexPath.section].sender.senderId
            if myJid == senderJid {
                // add action sheet
                let optionMenu = UIAlertController(title: nil, message: "Choose Option", preferredStyle: .actionSheet)
                let deleteForMyselfAction = UIAlertAction(title: "Delete for myself", style: .default, handler: { _ in
                    OneMessage.sharedInstance.deleteMessagesBasedOnIDFrom(jid: jid, messageID: self.messageList[self.selectedIndexPath.section].messageId)
                    // close Agrume overlay view, delete message from array used to present it and reload the data
                    self.agrume?.dismiss()
                    // check if the image is previously stored and delete key-value pair
                    if self.photosLocalIdentifiers[self.messageList[self.selectedIndexPath.section].messageId] != nil {
                        self.deleteKeyValueFromLocalIdentifiers(messageIdString: self.messageList[self.selectedIndexPath.section].messageId)
                    }
                    
                    self.messageList.remove(at: self.selectedIndexPath.section)
                    self.messagesCollectionView.reloadData()
                })
                let deleteForEveyoneAction = UIAlertAction(title: "Delete for everyone", style: .default, handler: { _ in
                    // firt delete locally...
                    OneMessage.sharedInstance.deleteMessagesBasedOnIDFrom(jid: jid, messageID: self.messageList[self.selectedIndexPath.section].messageId)
                    // ...and then delete remotely
                    OneMessage.sharedInstance.deleteMessage(jid: jid, messageID: self.messageList[self.selectedIndexPath.section].messageId)
                    // close Agrume overlay view, delete message from array used to present it and reload the data
                    self.agrume?.dismiss()
                    // check if the image is previously stored and delete key-value pair
                    if self.photosLocalIdentifiers[self.messageList[self.selectedIndexPath.section].messageId] != nil {
                        self.deleteKeyValueFromLocalIdentifiers(messageIdString: self.messageList[self.selectedIndexPath.section].messageId)
                    }
                    self.messageList.remove(at: self.selectedIndexPath.section)
                    self.messagesCollectionView.reloadData()
                })
                let cancelAction = UIAlertAction(title: "Cancel", style: .cancel)
                
                // add actions
                optionMenu.addAction(deleteForMyselfAction)
                optionMenu.addAction(deleteForEveyoneAction)
                optionMenu.addAction(cancelAction)
                
                // show UI AlertView
                self.getTopMostViewController()?.present(optionMenu, animated: true, completion: nil)
                
            } else {
                // if I'm the receiver, I can only delete message for myself
                OneMessage.sharedInstance.deleteMessagesBasedOnIDFrom(jid: jid, messageID: self.messageList[self.selectedIndexPath.section].messageId)
                // close Agrume overlay view, delete message from array used to present it and reload the data
                self.agrume?.dismiss()
                // check if the image is previously stored and delete key-value pair
                if self.photosLocalIdentifiers[self.messageList[self.selectedIndexPath.section].messageId] != nil {
                    self.deleteKeyValueFromLocalIdentifiers(messageIdString: self.messageList[self.selectedIndexPath.section].messageId)
                }
                self.messageList.remove(at: self.selectedIndexPath.section)
                self.messagesCollectionView.reloadData()
                
            }
            
        default:
            break
            //print("default value")
        }
        
    }
    
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromUIImagePickerControllerInfoKeyDictionary(_ input: [UIImagePickerController.InfoKey: Any]) -> [String: Any] {
    return Dictionary(uniqueKeysWithValues: input.map {key, value in (key.rawValue, value)})
}

// Helper function inserted by Swift 4.2 migrator.
private func convertFromUIImagePickerControllerInfoKey(_ input: UIImagePickerController.InfoKey) -> String {
    return input.rawValue
}
extension MatchesChatViewVC: UITextViewDelegate {
    
    func textViewDidEndEditing(_ textView: UITextView) {
        let searchText : String = textView.text ?? ""
        if searchText.count == 0
        {
            resetStackButton()
        }
    }
    func textViewDidChange(_ textView: UITextView) {
        let searchText : String = textView.text ?? ""
        let numLines : CGFloat = (textView.contentSize.height / (textView.font?.lineHeight ?? 20))
        manageHeight(Int(numLines))
        if searchText.count > 0
        {
            UIView.animate(withDuration: 0.3, delay: 0.0, animations: { [self] in
                bottomView.viewTxtChat.layer.borderColor = UIColor.royalPurple.cgColor
                bottomView.btn_attachment.isHidden = false
                bottomView.btn_camera.isHidden = true
                bottomView.btn_camera.alpha = 0
                bottomView.btn_gallery.isHidden = true
                bottomView.btn_gallery.alpha = 0
                bottomView.btn_location.isHidden = true
                bottomView.btn_location.alpha = 0

                bottomView.btn_send.isHidden = false
            })
        }
        else
        {
            bottomView.viewTxtChat.layer.borderColor = UIColor.slateGrey.cgColor
            resetStackButton()
        }
    }
    func manageHeight(_ numLines : Int) {
        let lineCount : Int = (numLines > 5) ? 5 : numLines
        let window = UIApplication.shared.windows.first
        let bottomPadding : CGFloat = window?.safeAreaInsets.bottom ?? 0
        let height : CGFloat = 45 + bottomPadding + CGFloat((lineCount * 18))
//        let width : CGFloat = window?.frame.width ?? 0
        y = (window?.frame.height ?? 0) - height
//        bottomView.frame = CGRect(x: 0, y: y - self.keyboardHeight, width: width, height: height)
        bottomView.txtChatHeight.constant = 27 + CGFloat((lineCount * 18))
        
        
        
    }
   
}
//extension MatchesChatViewVC: UITextFieldDelegate {
//    func textFieldDidEndEditing(_ textField: UITextField) {
//        let searchText : String = textField.text ?? ""
//        if searchText.count == 0
//        {
//            resetStackButton()
//        }
//    }
//    @objc func myTargetFunction(_ textField: UITextField) {
//    }
//
//    @objc func textFieldDidChange(_ textField: UITextField) {
//        let searchText : String = textField.text ?? ""
//        if searchText.count > 0
//        {
//            bottomView.btn_attachment.isHidden = false
//            bottomView.btn_camera.isHidden = true
//            bottomView.btn_gallery.isHidden = true
//            bottomView.btn_location.isHidden = true
//            bottomView.btn_send.isHidden = false
//        }
//        else
//        {
//            resetStackButton()
//        }
//    }
//}
