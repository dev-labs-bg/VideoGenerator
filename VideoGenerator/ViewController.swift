//
//  ViewController.swift
//  AudioPlayer
//
//  Created by Steliyan Hadzhidenev on 7/21/16.
//  Copyright © 2016 DevLabs. All rights reserved.
//

import UIKit
import AVKit
import Photos

class ViewController: UIViewController {
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    // Do any additional setup after loading the view, typically from a nib.
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  @IBOutlet weak var playButton: UIButton! {
    didSet {
      playButton.enabled = false
    }
  }
  
  @IBOutlet weak var recordButton: UIButton!
  
  @IBOutlet weak var buildButton: UIButton! {
    didSet {
      buildButton.enabled = false
    }
  }
  
  @IBAction func buildButtonPressed(sender: UIButton) {
    
    playButton.enabled = false
    playVideoButton.enabled = false
    sender.enabled = false
    recordButton.enabled = false
    
    let audioAsset = AVURLAsset(URL: getFileNameURL(), options: nil)
    let audioDuration = CMTimeGetSeconds(audioAsset.duration)
    
    let image = UIImage(named: "bleach")!
    let videoGenerator = VideoGenerator(withImages: [UIImage](count: 2, repeatedValue: image), andVideoDuration: Int(audioDuration))
    
    videoGenerator.build({ (progress) in
      print(progress)
      }, success: { (url) in
        print(url)
        // after successful generation of video based on images start merging audio and image video
        self.generateMovie(forAudioURL: self.getFileNameURL(), forVideoURL: url)
    }) { (error) in
      print(error)
    }
  }
  
  
  @IBAction func playVideoButtonPressed(sender: UIButton) {
    self.showMovie(urlToPlay)
  }
  
  @IBOutlet weak var playVideoButton: UIButton! {
    didSet {
      playVideoButton.enabled = false
    }
  }
  
  private var audioRecorder: AVAudioRecorder!
  
  private var audioPlayer: AVAudioPlayer!
  
  private var urlToPlay: NSURL!
  
  @IBAction func recordButtonPressed(sender: UIButton) {
    
    if sender.titleLabel?.text == "RECORD AUDIO" {
      let status = AVAudioSession.sharedInstance().recordPermission()
      
      if status == .Granted {
        startRecording()
      } else if status == .Undetermined {
        AVAudioSession.sharedInstance().requestRecordPermission({ (granted)-> Void in
          if granted {
            self.startRecording()
          } else {
            self.createAlertView(message: "Access denied. You shall not pass !!!!")
          }
        })
      } else {
        self.createAlertView(message: "Access denied. You shall not pass !!!!")
      }
      
    } else {
      audioRecorder.stop()
      sender.setTitle("RECORD AUDIO", forState: .Normal)
    }
  }
  
  @IBAction func playButtonPressed(sender: UIButton) {
    
    if sender.titleLabel?.text == "PLAY AUDIO"{
      recordButton.enabled = false
      playVideoButton.enabled = false
      buildButton.enabled = false
      sender.setTitle("PAUSE AUDIO", forState: .Normal)
      preparePlayer()
      audioPlayer.play()
    } else {
      recordButton.enabled = true
      buildButton.enabled = true
      if urlToPlay != nil {
        playVideoButton.enabled = true
      }
      audioPlayer.pause()
      sender.setTitle("PLAY AUDIO", forState: .Normal)
    }
  }
  
  private func getDocumentDirecory() -> NSURL {
    
    let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
    
    return NSURL(fileURLWithPath: paths.first!)
  }
  
  private func getFileNameURL() -> NSURL {
    let path = getDocumentDirecory().URLByAppendingPathComponent("test.caf")
    return path
  }
  
  private func startRecording() {
    /// before starting recording we need to create a record session otherwise no audio will be recorded
    self.setSessionPlayAndRecord()
    // stup the recorder
    self.setupRecorder()
    self.audioPlayer?.stop()
    self.audioRecorder.record()
    recordButton.setTitle("STOP AUDIO RECORDING", forState: .Normal)
    self.playButton.enabled = false
    self.playVideoButton.enabled = false
    self.buildButton.enabled = false
  }
  
  private func setupRecorder() {
    
    // set settings for the recorded file
    let recordSettings: [String: AnyObject] = [
      AVEncoderAudioQualityKey : AVAudioQuality.Max.rawValue,
      AVEncoderBitRateKey : 320000,
      AVNumberOfChannelsKey: 2,
      AVSampleRateKey : 44100.0
    ]
    
    do {
      // try to generate a audio recorder based on specified settings
      audioRecorder = try AVAudioRecorder(URL: getFileNameURL(), settings: recordSettings)
    } catch {
      print("Error")
    }
    
    audioRecorder.delegate = self
    audioRecorder.prepareToRecord()
  }
  
  func preparePlayer() {
    
    do {
      audioPlayer = try AVAudioPlayer(contentsOfURL: audioRecorder.url)
    } catch {
      print("Error")
    }
    audioPlayer.delegate = self
    audioPlayer.prepareToPlay()
    audioPlayer.volume = 1.0
    
  }
  
  private func setSessionPlayAndRecord() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(AVAudioSessionCategoryPlayAndRecord)
    } catch let error as NSError {
      print("could not set session category")
      print(error.localizedDescription)
    }
    do {
      try session.setActive(true)
    } catch let error as NSError {
      print("could not make session active")
      print(error.localizedDescription)
    }
  }
  
  
  private func generateMovie(forAudioURL audioUrl: NSURL, forVideoURL videoUrl: NSURL) {
    /// create new mix composition
    let mixComposition = AVMutableComposition()
    
    /// create new audio asset for the recorded ausio
    let audioAsset = AVURLAsset(URL: audioUrl, options: nil)
    /// define audio time range
    let audioTimeRange = CMTimeRange(start: kCMTimeZero, duration: audioAsset.duration)
    
    /// create an audio composition which will be merged to the video
    let audioCompositon = mixComposition.addMutableTrackWithMediaType(AVMediaTypeAudio, preferredTrackID: kCMPersistentTrackID_Invalid)
    /// access the audio track which will be merged
    if let audioTrack = audioAsset.tracksWithMediaType(AVMediaTypeAudio).first {
      do {
        // if successful access to the audio file add the time range to the audio composition at the begining
        try audioCompositon.insertTimeRange(audioTimeRange, ofTrack: audioTrack ,atTime: kCMTimeZero)
      } catch let error as NSError {
        print(error.localizedDescription)
      }
      
      /// after setting the audio composition the video composition should be prepared
      let videoAsset = AVURLAsset(URL: videoUrl, options: nil)
      /// define video time range
      let videoTimeRange = CMTimeRange(start: kCMTimeZero, duration: videoAsset.duration)
      
      /// create video composition which will be merged to the audio
      let videoComposition = mixComposition.addMutableTrackWithMediaType(AVMediaTypeVideo, preferredTrackID: kCMPersistentTrackID_Invalid)
      /// access the video which will be merged
      if let videoTrack = videoAsset.tracksWithMediaType(AVMediaTypeVideo).first {
        do {
          try videoComposition.insertTimeRange(videoTimeRange, ofTrack: videoTrack ,atTime: kCMTimeZero)
        } catch let error as NSError {
          print(error.localizedDescription)
        }
        
        /// specify the path of the merged movie
        if let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first {
          let videoOutputURL = NSURL(fileURLWithPath: documentsPath).URLByAppendingPathComponent("finalmovie.m4v")
          
          do {
            // delete the old version of the file
            try NSFileManager.defaultManager().removeItemAtURL(videoOutputURL)
          } catch { }
          
          /// create an export sessions
          let exportSession = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)
          
          // define the exported type and url where the movie will be generated
          exportSession?.outputFileType = AVFileTypeMPEG4
          exportSession?.outputURL = videoOutputURL
          
          exportSession?.exportAsynchronouslyWithCompletionHandler({
            
            dispatch_async(dispatch_get_main_queue(), {
              /// after the export finishes get back to the main thread
              self.exportDidFinish(withExportSession: exportSession)
            })
          })
        }
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
            self.urlToPlay = url
            self.playVideoButton.enabled = true
            self.recordButton.enabled = true
            self.playButton.enabled = true
            self.buildButton.enabled = true
            self.createAlertView(message: "Successfully generated movie")
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
    /**
     *  Check if the status of the export session is completed and if it is save it to the photo library
     */
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

extension ViewController: AVAudioRecorderDelegate {
  
  func audioRecorderDidFinishRecording(recorder: AVAudioRecorder, successfully flag: Bool) {
    playButton.enabled = true
    buildButton.enabled = true
    recordButton.setTitle("RECORD AUDIO", forState: .Normal)
  }
  
  func audioRecorderEncodeErrorDidOccur(recorder: AVAudioRecorder, error: NSError?) {
    print("Error while recording audio \(error?.localizedDescription)")
  }
}

extension ViewController: AVAudioPlayerDelegate {
  func audioPlayerDidFinishPlaying(player: AVAudioPlayer, successfully flag: Bool) {
    recordButton.enabled = true
    buildButton.enabled = true
    playButton.setTitle("PLAY AUDIO", forState: .Normal)
  }
  
  func audioPlayerDecodeErrorDidOccur(player: AVAudioPlayer, error: NSError?) {
    print("Error while playing audio \(error?.localizedDescription)")
  }
}

extension UIImage {
  
  internal func resizeImageToSize(size: CGSize) -> UIImage {
    
    UIGraphicsBeginImageContextWithOptions(size, false, 0.0)
    drawInRect(CGRectMake(0, 0, size.width, size.height))
    let imageResized = UIGraphicsGetImageFromCurrentImageContext()
    UIGraphicsEndImageContext()
    
    return imageResized
  }
  
  /**
   Method to resize an image based on the screen width
   
   - returns: Resized image
   */
  internal func resizeImage() -> UIImage? {
    
    let minDimension = min(size.width, size.height)
    let screenWidth = UIScreen.mainScreen().bounds.width
    var scaledImage: UIImage!
    
    if minDimension > screenWidth {
      
      let scaleFactor: CGFloat = minDimension / screenWidth
      
      UIGraphicsBeginImageContext(CGSize(width: size.width / scaleFactor, height: size.height / scaleFactor))
      drawInRect(CGRect(x: 0, y: 0, width: size.width / scaleFactor, height: size.height / scaleFactor))
      scaledImage = UIGraphicsGetImageFromCurrentImageContext()
      UIGraphicsEndImageContext()
    } else {
      scaledImage = self
    }
    
    return scaledImage
  }
}

