//
//  MainNC.swift
//
//  Created by Norbert Thies on 10.08.18.
//  Copyright © 2018 Norbert Thies. All rights reserved.
//

import UIKit
import MessageUI
import NorthLib


class MainNC: NavigationController, UIStyleChangeDelegate,
              MFMailComposeViewControllerDelegate {
  
  private var threeFingerAlertOpen: Bool = false
  var showAnimations = false
  lazy var consoleLogger = Log.Logger()
  lazy var viewLogger = Log.ViewLogger()
  lazy var fileLogger = Log.FileLogger()
  var feederContext: FeederContext!
  let net = NetAvailability()
  
  var authenticator: Authenticator? { return feederContext.authenticator }

  @Key("dataPolicyAccepted")
  public var dataPolicyAccepted: Bool
  
  static var singleton: MainNC!
  private var isErrorReporting = false
  private var isForeground = false
  
  override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    Notification.send(Const.NotificationNames.viewSizeTransition,
                      content: size,
                      error: nil,
                      sender: nil)
  }

  /// Enable logging to file and otional to view
  func setupLogging() {
    let logView = viewLogger.logView
    logView.isHidden = true
    view.addSubview(logView)
    logView.pinToView(view)
    Log.append(logger: consoleLogger, /*viewLogger,*/ fileLogger)
    Log.minLogLevel = .Debug
    HttpSession.isDebug = false
    PdfRenderService.isDebug = false
    ZoomedImageView.isDebug = false
    Log.onFatal { msg in 
      self.log("fatal closure called, error id: \(msg.id)") 
      self.reportFatalError(err: msg)
    }
    net.onChange { (flags) in self.log("net changed: \(flags)") }
    net.whenUp { self.log("Network up") }
    net.whenDown { self.log("Network down") }
    if !net.isAvailable { error("Network not available") }
    let nd = UIApplication.shared.delegate as! AppDelegate
    nd.onSbTap { tview in
      if nd.wantLogging {
        if logView.isHidden {
          self.view.bringSubviewToFront(logView)
          logView.scrollToBottom()
          logView.isHidden = false
        }
        else {
          self.view.sendSubviewToBack(logView)
          logView.isHidden = true
        }
      }
    }
    log("App: \"\(App.name)\" \(App.bundleVersion)-\(App.buildNumber)\n" +
        "\(Device.singleton): \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n" +
        "Path: \(Dir.appSupportPath)")
  }
  
  func produceErrorReport(recipient: String, subject: String = "Feedback", 
                          completion: (()->())? = nil) {
    if MFMailComposeViewController.canSendMail() {
      let mail =  MFMailComposeViewController()
      let screenshot = UIWindow.screenshot?.jpeg
      let logData = fileLogger.data
      mail.mailComposeDelegate = self
      mail.setToRecipients([recipient])
      
      var tazIdText = ""
      let data = DefaultAuthenticator.getUserData()
      if let tazID = data.id, tazID.isEmpty == false {
        tazIdText = " taz-ID: \(tazID)"
      }
      
      mail.setSubject("\(subject) \"\(App.name)\" (iOS)\(tazIdText)")
      mail.setMessageBody("App: \"\(App.name)\" \(App.bundleVersion)-\(App.buildNumber)\n" +
        "\(Device.singleton): \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)\n\n...\n",
        isHTML: false)
      if let screenshot = screenshot {
        mail.addAttachmentData(screenshot, mimeType: "image/jpeg",
                               fileName: "taz.neo-screenshot.jpg")
      }
      if let logData = logData {
        mail.addAttachmentData(logData, mimeType: "text/plain",
                               fileName: "taz.neo-logfile.txt")
      }
      self.topmostModalVc.present(mail, animated: true, completion: completion)
    }
  }
  
  func mailComposeController(_ controller: MFMailComposeViewController,
    didFinishWith result: MFMailComposeResult, error: Error?) {
    controller.dismiss(animated: true)
    isErrorReporting = false
  }
  
  @objc func twoFingerErrorReportActivated(_ sender: UIGestureRecognizer) {
    showFeedbackErrorReport()
  }
  
  func showFeedbackErrorReport(_ feedbackType: FeedbackType? = nil) {
    if isErrorReporting == true { return }//Prevent multiple Calls
    isErrorReporting = true
    
    FeedbackComposer.showWith(logData: fileLogger.data,
                              feederContext: self.feederContext,
                              feedbackType: feedbackType) { didSend in
      print("Feedback send? \(didSend)")
      self.isErrorReporting = false
    }
  }
  
  func reportFatalError(err: Log.Message) {
    guard !isErrorReporting else { return }
    isErrorReporting = true
    if self.presentedViewController != nil {
      dismiss(animated: false)
    }
    Alert.confirm(title: "Interner Fehler",
                  message: "Es liegt ein schwerwiegender interner Fehler vor, möchten Sie uns " +
                           "darüber mit einer Nachricht informieren?\n" +
                           "Interne Fehlermeldung:\n\(err)") { yes in
      if yes {
        self.produceErrorReport(recipient: "app@taz.de", subject: "Interner Fehler") 
      }
      else { self.isErrorReporting = false }
    }
  }
  
  @objc func threeFingerTouch(_ sender: UIGestureRecognizer) {
    if threeFingerAlertOpen { return } else { threeFingerAlertOpen = true }
    var actions: [UIAlertAction] = [
      Alert.action("Feedback senden") {_ in self.showFeedbackErrorReport(.feedback) },
      Alert.action("Fehlerbericht senden") {_ in self.showFeedbackErrorReport(.error) },
      Alert.action("Alle Ausgaben löschen") {_ in self.deleteAll() },
      Alert.action("Kundendaten löschen (Abmelden)") {_ in self.deleteUserData() }]
    
    if App.isAlpha {
      actions.append(Alert.action("Abo-Verknüpfung löschen (⍺)") {[weak self] _ in self?.unlinkSubscriptionId() })
      actions.append(Alert.action("Abo-Push anfordern (⍺)") {[weak self] _ in self?.testNotification(type: NotificationType.subscription) })
      actions.append(Alert.action("Download-Push anfordern (⍺)") {[weak self] _ in self?.testNotification(type: NotificationType.newIssue) })
      actions.append(Alert.action("Protokoll an/aus (⍺)") {[weak self] _ in
        guard let self = self else { return }
        let logView = self.viewLogger.logView
        if logView.isHidden {
          self.view.bringSubviewToFront(logView)
          logView.scrollToBottom()
          logView.isHidden = false
        }
        else {
          self.view.sendSubviewToBack(logView)
          logView.isHidden = true
        }
      })
    }
    let userInfo = "\(feederContext.isAuthenticated == false ? "NICHT ANGEMELDET" : "angemeldet" ), gespeicherte taz-ID: \(DefaultAuthenticator.getUserData().id ?? "-")"
    
    let appTitle = App.isAlpha ? "Alpha" : App.isBeta ? "Beta" : "taz"
    
    
    Alert.actionSheet(title: "\(appTitle) (v) \(App.version)-\(App.buildNumber)\n\(userInfo)",
                      actions: actions) { [weak self] in
      self?.threeFingerAlertOpen = false
    }
  }
  
  func setupTopMenus() {
    let reportLPress2 = UILongPressGestureRecognizer(target: self,
        action: #selector(twoFingerErrorReportActivated))
    let reportLPress3 = UILongPressGestureRecognizer(target: self,
        action: #selector(threeFingerTouch))
    reportLPress2.numberOfTouchesRequired = 2
    reportLPress3.numberOfTouchesRequired = 3
    
    
    if let targetView = UIApplication.shared.keyWindow {
      /// currently never executed due keyWindow was nil when logged in
      targetView.isUserInteractionEnabled = true
      targetView.addGestureRecognizer(reportLPress2)
      targetView.addGestureRecognizer(reportLPress3)
    }
    else if let delegate = UIApplication.shared.delegate as? AppDelegate,
            let targetWindow = delegate.window {
      /// ...improved version of previous comparrison ...should be standalone!
      targetWindow.isUserInteractionEnabled = true
      targetWindow.addGestureRecognizer(reportLPress2)
      targetWindow.addGestureRecognizer(reportLPress3)
    }
    else {
      self.view.isUserInteractionEnabled = true
      self.view.addGestureRecognizer(reportLPress2)
      self.view.addGestureRecognizer(reportLPress3)
    }
  }

  func showIssueVC() {
    feederContext.setupRemoteNotifications()
    let ivc = IssueVC(feederContext: feederContext)
    replaceTopViewController(with: ivc, animated: false)
  }
  
  func showIntro(closure: @escaping ()->()) {
    Notification.receiveOnce("resourcesReady") { [weak self] _ in
      guard let self = self else { return }
      self.debug("Showing Intro")
      let introVC = IntroVC()
      let feeder = self.feederContext.storedFeeder!
      introVC.htmlDataPolicy = feeder.dataPolicy
      introVC.htmlIntro = feeder.welcomeSlides
      Notification.receiveOnce("dataPolicyAccepted") { [weak self] notif in
        self?.popViewController(animated: false)
        let kc = Keychain.singleton
        kc["dataPolicyAccepted"] = "true"
        closure()
      }
      self.pushViewController(introVC, animated: false)
      onMainAfter(0.3) { [weak self] in
        guard let self = self else { return }
        self.feederContext.getOvwIssues(feed: self.feederContext.defaultFeed, count: 4)
      }
    }
    feederContext.updateResources(toVersion: -1)
  }
  
  // Logs Keychain variables if in debug mode
  func logKeychain(msg: String? = nil) {
    var str = ""
    for k in ["id", "password", "token", "dataPolicyAccepted"] {
      var val = Keychain.singleton[k]
      if k == "password" && val != nil { val = "defined (but hidden on purpose)" }
      else if k == "token" && val != nil { val = val![0..<30] }
      str += "  \(k): \(val ?? "undefined")\n"
    }
    str = str[0..<str.count-1]
    var intro = "Keychain variables"
    if let msg = msg { intro += " (\(msg))" }
    intro += ":\n"
    debug("\(intro)\(str)")
  }
    
  func startup() {
    let dfl = Defaults.singleton
    let oneWeek = 7*24*3600
    let nStarted = dfl["nStarted"]!.int!
    let lastStarted = dfl["lastStarted"]!.usTime
    debug("Startup: #\(nStarted), last: \(lastStarted.isoDate())")
    logKeychain(msg: "initial")
    let now = UsTime.now()
    self.showAnimations = (nStarted < 2) || (now.sec - lastStarted.sec) > oneWeek
    IssueVC.showAnimations = self.showAnimations
    SectionVC.showAnimations = self.showAnimations
    ContentTableVC.showAnimations = self.showAnimations
    dfl["nStarted"] = "\(nStarted + 1)"
    dfl["lastStarted"] = "\(now.sec)"
    if !dataPolicyAccepted {
      showIntro() { self.showIssueVC() }
    }
    else {
      feederContext.updateResources(toVersion: -1)
      showIssueVC()
    }
  } 
  
  func goingBackground() {
    isForeground = false
    ArticleDB.save()
    debug("Going background")
  }
  
  func goingForeground() {
    isForeground = true
    debug("Entering foreground")
  }
  
  func appWillTerminate() {
    ArticleDB.save()//You have 5 Seconds!!
    debug("App is going to be terminated")
  }
 
  func deleteAll() {
    popToRootViewController(animated: false)
    feederContext.gqlFeeder.status?.feeds = []
    feederContext.gqlFeeder.gqlSession?.session.invalidateAndCancel()
    feederContext.dloader.killAll()
    ArticleDB.singleton.close()
    /// Remove all content
    for f in Dir.appSupport.scan() {
      debug("remove: \(f)")
      File(f).remove()
    }
    log("delete all done successfully")
    exit(0)
  }
  
  func unlinkSubscriptionId() {
    authenticator?.unlinkSubscriptionId()
  }
  
  func deleteUserData() {
    SimpleAuthenticator.deleteUserData()
    let dfl = Defaults.singleton
    let kc = Keychain.singleton
    kc["dataPolicyAccepted"] = nil
    dfl["isTextNotification"] = "true"
    dfl["nStarted"] = "0"
    dfl["lastStarted"] = "0"
    dfl["installationId"] = nil
    feederContext.gqlFeeder.authToken = nil
    feederContext.endPolling()
    logKeychain(msg: "after delete")
  }
  
  func testNotification(type: NotificationType) {
    if let pushToken = Defaults.singleton["pushToken"] {
      feederContext.gqlFeeder.testNotification(pushToken: pushToken, request: type) {_ in}
    }
  }
  
  func setupFeeder() {
    Notification.receiveOnce("feederReady") { notification in
      guard let fctx = notification.sender as? FeederContext else { return }
      self.debug(fctx.storedFeeder.toString())
      self.startup()
    }
    let feeder = Defaults.currentFeeder
    self.feederContext =
      FeederContext(name: feeder.name, url: feeder.url, feed: feeder.feed)
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    pushViewController(StartupVC(), animated: false)
    MainNC.singleton = self
    isNavigationBarHidden = true
    isForeground = true
    // Disallow leaving view controllers IssueVC and IntroVC by edge swipe
    onPopViewController { vc in
      if vc is IssueVC || vc is IntroVC {
        return false
      }
      return true
    }
    setupTopMenus()
    setupLogging()
    Notification.receive(UIApplication.willResignActiveNotification) { _ in
      self.goingBackground()
    }
    Notification.receive(UIApplication.willEnterForegroundNotification) { _ in
      self.goingForeground()
    }
    Notification.receive(UIApplication.willTerminateNotification) { _ in
      self.appWillTerminate()
    }
    setupFeeder()
    registerForStyleUpdates()
  } // viewDidLoad
  
  func applyStyles() {
    self.view.backgroundColor = Const.SetColor.HBackground.color
    setNeedsStatusBarAppearanceUpdate()

  }
  
  override var preferredStatusBarStyle: UIStatusBarStyle {
    return Defaults.darkMode ?  .lightContent : .default
  }

} // MainNC
