//
//  FeedbackComposer.swift
//  taz.neo
//
//  Created by Ringo Müller-Gromes on 25.09.20.
//  Copyright © 2020 Norbert Thies. All rights reserved.
//

import Foundation
import UIKit
import NorthLib
/**
 TODOS
 - Check if still working in Article & more!!
 - Overlay, seams to work testet in Simulator in ArticleCV && deinit for Overlay Called
 - not for ZoomedImageView? =>  its ContentImageVC => also not => Ticket created #12863
 - ZoomedImageView
 - WORKAROUND DONE fix screenshot fullscreen border, not using overlay, not using zoomed ImageView
 - FEEDBACK REQUIRED make the buttons similar 
 */

public enum FeedbackType { case error, feedback, fatalError }

open class FeedbackComposer : DoesLog{
  
  public static func showWith(logData: Data? = nil,
                              feederContext: FeederContext,
                              feedbackType: FeedbackType? = nil,
                              finishClosure: @escaping ((Bool) -> ())) {
    let screenshot = UIWindow.screenshot
    let deviceData = DeviceData()
    
    let feedbackHandler: (Any?) -> Void = { _ in
      FeedbackComposer.send(type: FeedbackType.feedback,
                            feederContext: feederContext,
                            finishClosure: finishClosure)
    }
    
    let errorReportHandler: (Any?) -> Void = { _ in
      FeedbackComposer.send(type: FeedbackType.error,
                            deviceData: deviceData,
                            screenshot: screenshot,
                            logData: logData,
                            feederContext: feederContext,
                            finishClosure: finishClosure)
    }
    
    if feedbackType == .error || feedbackType == .fatalError {
      errorReportHandler(nil); return
    }
    else if feedbackType == .feedback {
      feedbackHandler(nil); return
    }
    
    let feedbackAction = UIAlertAction(title: "Feedback geben",
                                       style: .default,
                                       handler: feedbackHandler)
    
    let errorReportAction = UIAlertAction(title: "Fehler melden",
                                          style: .destructive,
                                          handler: errorReportHandler)
    
    let cancelAction = UIAlertAction(title: "Abbrechen", style: .cancel) { _ in finishClosure(false) }
    
    Alert.message(title: "Rückmeldung", message: "Möchten Sie einen Fehler melden oder uns Feedback geben?", actions: [feedbackAction, errorReportAction, cancelAction])
  }
  
  public static func send(type: FeedbackType,
                          deviceData: DeviceData? = nil,
                          screenshot: UIImage? = nil,
                          logData: Data? = nil,
                          feederContext: FeederContext,
                          finishClosure: @escaping ((Bool) -> ())) {
    
    guard var currentVc = UIViewController.top() else {
      print("Error, no Controller to Present")
      return;
    }
    
    var feedbackBottomSheet : FullscreenBottomSheet?
    
    let feedbackViewController
      = FeedbackViewController(
        type: type,
        screenshot: screenshot,
        deviceData: deviceData,
        logData: logData,
        feederContext: feederContext){
          feedbackBottomSheet?.slide(toOpen: false, animated: true)
          
    }
    
    if currentVc.isKind(of: UIAlertController.self),
       let presenting = currentVc.presentingViewController {
      currentVc = presenting
      feedbackViewController.updateViewSize(UIWindow.size)
    }
                                                       
    feedbackBottomSheet = FullscreenBottomSheet(slider: feedbackViewController,
                                              into: currentVc)
    feedbackBottomSheet?.sliderView.backgroundColor = Const.SetColor.CTBackground.color
    feedbackBottomSheet?.coverageRatio = 1.0
    
    let cancelHandler: ()->() = {
        guard let feedbackBottomSheet = feedbackBottomSheet else { return }
        let type
          = (feedbackBottomSheet.sliderVC as? FeedbackViewController)?.type
          ?? .feedback
        
        feedbackBottomSheet.slide(toOpen: true, animated: true)
        Alert.confirm(message: type == .feedback ? "Feedback..." : "Fehlerbericht...",
                      okText: "löschen & beenden",
                      cancelText: "weiter bearbeiten",
                      isDestructive: true) { (close) in
                        if close {
                          feedbackBottomSheet.slide(toOpen: false, animated: true)
                        }
        }
    }
    feedbackBottomSheet?.onUserSlideToClose = cancelHandler
    feedbackViewController.requestCancel = cancelHandler
    
    feedbackBottomSheet?.onClose(closure: { (slider) in
      finishClosure(feedbackViewController.sendSuccess)
      feedbackBottomSheet = nil//Important the memory leak!
    })
    feedbackBottomSheet?.open()
  }
}



