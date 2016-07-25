//
//  VideoGeneratorViewController.swift
//  VideoGenerator
//
//  Created by Steliyan Hadzhidenev on 7/21/16.
//  Copyright © 2016 DevLabs. All rights reserved.
//

import UIKit
import AVFoundation
import AVKit
import Photos

class VideoGeneratorViewController: UIViewController {
  
  override func viewDidLoad() {
    super.viewDidLoad()
  }
  
  
  @IBAction func buildPLS(sender: UIButton) {
    
    print(NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).last)
    
    let image = UIImage(named: "bleach")!
    let videoGenerator = VideoGenerator(withImages: [UIImage](count: 2, repeatedValue: image), andVideoDuration: 20)
    
    videoGenerator.build({ (progress) in
      print(progress)
      }, success: { (url) in
        print(url)
        self.generateMovie(forAudioURL: NSURL(), forVideoURL: url)
    }) { (error) in
      print(error)
    }
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  private func generateMovie(forAudioURL audioUrl: NSURL, forVideoURL videoUrl: NSURL) {
    let mixComposition = AVMutableComposition()
    
    let audioFilePath = NSBundle.mainBundle().pathForResource("song", ofType: "mp3")!
    let _audioUrl = NSURL(fileURLWithPath: audioFilePath)
    let audioAsset = AVURLAsset(URL: _audioUrl, options: nil)
    let audioTimeRange = CMTimeRange(start: kCMTimeZero, duration: audioAsset.duration)
    
    
    let audioCompositon = mixComposition.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
    if let audioTrack = audioAsset.tracksWithMediaType(AVMediaTypeAudio).first {
      do {
        try audioCompositon.insertTimeRange(audioTimeRange, ofTrack: audioTrack ,atTime: kCMTimeZero)
      } catch let error as NSError {
        print(error.localizedDescription)
      }
      
      let videoAsset = AVURLAsset(URL: videoUrl, options: nil)
      let videoTimeRange = CMTimeRange(start: kCMTimeZero, duration: videoAsset.duration)
      
      let videoComposition = mixComposition.addMutableTrackWithMediaType(AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
      if let videoTrack = videoAsset.tracksWithMediaType(AVMediaTypeVideo).first {
        do {
          try videoComposition.insertTimeRange(videoTimeRange, ofTrack: videoTrack ,atTime: kCMTimeZero)
        } catch let error as NSError {
          print(error.localizedDescription)
        }
        
        let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] as NSString
        let videoOutputURL = NSURL(fileURLWithPath: documentsPath.stringByAppendingPathComponent("FinalMovie.m4v"))
        
        do {
          try NSFileManager.defaultManager().removeItemAtURL(videoOutputURL)
        } catch { }
        
        let exportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)
        exportSession?.outputFileType = AVFileTypeMPEG4
        exportSession?.outputURL = videoOutputURL
        
        exportSession?.exportAsynchronouslyWithCompletionHandler({
          dispatch_async(dispatch_get_main_queue(), {
            self.exportDidFinish(withExportSession: exportSession)
          })
        })
      }
    }
  }
  
  private func createAlertView(title: String? = "", message: String?) {
    let refreshAlert = UIAlertController(title: title, message: message, preferredStyle: .Alert)
    
    refreshAlert.addAction(UIAlertAction(title: "OK", style: .Default, handler: { (action: UIAlertAction!) in
      refreshAlert.dismissViewControllerAnimated(true, completion: nil)
    }))
    
    presentViewController(refreshAlert, animated: true, completion: nil)
  }
  
  private func showMovie(url: NSURL) {
    let player = AVPlayer(URL: url)
    let playerController = AVPlayerViewController()
    playerController.player = player
    self.presentViewController(playerController, animated: true) {
      player.play()
    }
  }
  
  private func saveVideoToPhotos(forUrl url: NSURL) {
    PHPhotoLibrary.sharedPhotoLibrary().performChanges({
      PHAssetChangeRequest.creationRequestForAssetFromVideoAtFileURL(url)
      }, completionHandler: { (completed, error) in
        if completed {
          dispatch_async(dispatch_get_main_queue()) {
            self.showMovie(url)
          }
        }
        
        if error != nil {
          dispatch_async(dispatch_get_main_queue()) {
            self.createAlertView(message: error?.localizedDescription)
          }
        }
    })
  }
  
  private func exportDidFinish(withExportSession session: AVAssetExportSession?) {
    if session?.status == .Completed {
      if let outputUrl = session?.outputURL {
        let accessToPhotosStatus = PHPhotoLibrary.authorizationStatus()
        
        if accessToPhotosStatus == .Authorized {
          saveVideoToPhotos(forUrl: outputUrl)
        } else if accessToPhotosStatus == .NotDetermined {
          PHPhotoLibrary.requestAuthorization({ (status) in
            if status == .Authorized {
              self.saveVideoToPhotos(forUrl: outputUrl)
            } else {
              self.createAlertView(message: "Access denied. You shall not pass !!!!")
            }
          })
        } else {
          self.createAlertView(message: "Access denied. You shall not pass !!!!")
        }
      }
    }
  }
}
