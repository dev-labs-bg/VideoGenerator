//
//  VideoGenerator.swift
//  VideoGenerator
//
//  Created by Steliyan Hadzhidenev on 7/21/16.
//  Copyright © 2016 DevLabs. All rights reserved.
//

import UIKit
import AVFoundation

let kErrorDomain = "VideoGenerator"
let kFailedToStartAssetWriterError = 0
let kFailedToAppendPixelBufferError = 1
let kFailedToFetchDirectory = 2

class VideoGenerator: NSObject {
  
  // MARK: - Singleton properties
  
  // MARK: - Static properties
  
  // MARK: - Public properties
  
  // MARK: - Public methods
  
  /**
   Public method to start a video generation
   
   - parameter progress: A block which will track the progress of the generation
   - parameter success:  A block which will be called after successful generation of video
   - parameter failure:  A blobk which will be called on a failure durring the generation of the video
   */
  internal func build(progress: (NSProgress -> Void), success: (NSURL -> Void), failure: (NSError -> Void)) {
    
    /// define the input and output size of the video which will be generated
    let inputSize = UIScreen.mainScreen().bounds
    let outputSize = UIScreen.mainScreen().bounds
    var error: NSError?
    
    /// check if the documents directory can be accessed
    if let documentsPath = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first {
      
      /// generate a video output url
      let videoOutputURL = NSURL(fileURLWithPath: documentsPath).URLByAppendingPathComponent("test.m4v")
      
      do {
        // try to delete the old generated video
        try NSFileManager.defaultManager().removeItemAtURL(videoOutputURL)
      } catch { }
      
      do {
        // try to create a asset writer for videos pointing to the video url
        try videoWriter = AVAssetWriter(URL: videoOutputURL, fileType: AVFileTypeMPEG4)
      } catch let writerError as NSError {
        error = writerError
        videoWriter = nil
      }
      
      /// check if the creation is successful
      if let videoWriter = videoWriter {
        
        // create the basic video settings
        let videoSettings: [String : AnyObject] = [
          AVVideoCodecKey  : AVVideoCodecH264,
          AVVideoWidthKey  : outputSize.width,
          AVVideoHeightKey : outputSize.height,
          //                AVVideoCompressionPropertiesKey : [
          //                  AVVideoAverageBitRateKey : NSInteger(1000000),
          //                  AVVideoMaxKeyFrameIntervalKey : NSInteger(16),
          //                  AVVideoProfileLevelKey : AVVideoProfileLevelH264BaselineAutoLevel
          //                ]
        ]
        
        /// create a video writter input
        let videoWriterInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: videoSettings)
        
        /// create setting for the pixel buffer
        let sourceBufferAttributes: [String : AnyObject] = [
          (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32ARGB),
          (kCVPixelBufferWidthKey as String): Float(inputSize.width),
          (kCVPixelBufferHeightKey as String):  Float(inputSize.height)
        ]
        
        
        /// create pixel buffer for the input writter and the pixel buffer settings
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: sourceBufferAttributes)
        
        assert(videoWriter.canAddInput(videoWriterInput))
        
        // add the input writter to the video asset
        videoWriter.addInput(videoWriterInput)
        
        // check if a write session can be executed
        if videoWriter.startWriting() {
          // if it is possible set the start time of the session (current at the begining)
          videoWriter.startSessionAtSourceTime(kCMTimeZero)
          assert(pixelBufferAdaptor.pixelBufferPool != nil)
          
          /// create/access separate queue for the generation process
          let media_queue = dispatch_queue_create("mediaInputQueue", DISPATCH_QUEUE_SERIAL)
          
          // start video generation on a separate queue
          videoWriterInput.requestMediaDataWhenReadyOnQueue(media_queue, usingBlock: { () -> Void in
            
            /// each image represents a portion of the video and based on the count of the images the duration of each frame is calculated
            let frameDuration = CMTime(seconds: Double(self.duration / self.images.count), preferredTimescale: 1)
            let currentProgress = NSProgress(totalUnitCount: Int64(self.images.count))
            
            var frameCount: Int64 = 0
            var remainingPhotos = [UIImage](self.images)
            
            /**
             *  The process of appending images should continue untill the input media writter is ready and there are still images to be appended
             */
            while (videoWriterInput.readyForMoreMediaData && !remainingPhotos.isEmpty) {
              
              // get next image which will be appended
              let nextPhoto = remainingPhotos.removeAtIndex(0)
              
              // calculate the frame duration
              let lastFrameTime = self.images.count > 1 ? CMTime(seconds: Double(frameCount - self.images.count), preferredTimescale: Int32(self.duration)) : CMTime(seconds: Double(self.duration), preferredTimescale: 1)
              let presentationTime = frameCount == 0 ? lastFrameTime : CMTimeAdd(lastFrameTime, frameDuration)
              
              // check if the pixel append is successful otherwise an error will be generated
              if !self.appendPixelBufferForImage(nextPhoto, pixelBufferAdaptor: pixelBufferAdaptor, presentationTime: presentationTime) {
                error = NSError(
                  domain: kErrorDomain,
                  code: kFailedToAppendPixelBufferError,
                  userInfo: [
                    "description": "AVAssetWriterInputPixelBufferAdapter failed to append pixel buffer",
                    "rawError": videoWriter.error ?? "(none)"
                  ]
                )
                
                break
              }
              
              // increise the frame count
              frameCount += 1
              
              currentProgress.completedUnitCount = frameCount
              
              // after each successful append of an image track the current progress
              progress(currentProgress)
            }
            
            // after all images are appended the writting shoul be marked as finished
            videoWriterInput.markAsFinished()
            
            // the completion is made with a completion handler which will return the url of the generated video or an error
            videoWriter.finishWritingWithCompletionHandler { () -> Void in
              if error == nil {
                success(videoOutputURL)
              } else {
                print(error?.localizedDescription)
              }
              
              self.videoWriter = nil
            }
          })
        } else {
          error = NSError(
            domain: kErrorDomain,
            code: kFailedToStartAssetWriterError,
            userInfo: ["description": "AVAssetWriter failed to start writing"]
          )
        }
      }
      
      if let error = error {
        failure(error)
      }
    } else {
      error = NSError(
        domain: kErrorDomain,
        code: kFailedToFetchDirectory,
        userInfo: ["description": "Can't find the Documents directory"]
      )
      
      if let error = error {
        failure(error)
      }
    }
  }
  
  
  // MARK: - Initialize/Livecycle methods
  
  /**
   Initialisation method of the class
   
   - parameter _images:     The images from which a video will be generated
   - parameter _duration: The duration of the movie which will be generated
   */
  init(withImages _images: [UIImage], andVideoDuration _duration: Int) {
    
    super.init()
    images = _images
    duration = _duration
  }
  
  // MARK: - Override methods
  
  // MARK: - Private properties
  
  /// private property to store the images from which a video will be generated
  private var images: [UIImage]!
  
  /// private property to store the duration of the generated video
  private var duration: Int!
  
  /// private property to store a video asset writer (optional because the generation might fail)
  private var videoWriter: AVAssetWriter?
  
  // MARK: - Private methods
  
  /**
   Private method to append pixels to a pixel buffer
   
   - parameter url:                The image which pixels will be appended to the pixel buffer
   - parameter pixelBufferAdaptor: The pixel buffer to which new pixels will be added
   - parameter presentationTime:   The duration of each frame of the video
   
   - returns: True or false depending on the action execution
   */
  private func appendPixelBufferForImage(image: UIImage, pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor, presentationTime: CMTime) -> Bool {
    
    /// at the beginning of the append the status is false
    var appendSucceeded = false
    
    /**
     *  The proccess of appending new pixels is puted inside a autoreleasepool
     */
    autoreleasepool {
      
      // check posibilitty of creating a pixel buffer pool
      if let pixelBufferPool = pixelBufferAdaptor.pixelBufferPool {
        let pixelBufferPointer = UnsafeMutablePointer<CVPixelBuffer?>.alloc(1)
        let status: CVReturn = CVPixelBufferPoolCreatePixelBuffer(
          kCFAllocatorDefault,
          pixelBufferPool,
          pixelBufferPointer
        )
        
        /// the image which pixels will be appended needs to be resized to the bounds of the screen
        let resisedImage = image.resizeImageToSize(UIScreen.mainScreen().bounds.size)
        
        /// check if the memory of the pixel buffer pointer can be accessed and the creation status is 0
        if let pixelBuffer = pixelBufferPointer.memory where status == 0 {
          
          // if the condition is satisfied append the image pixels to the pixel buffer pool
          fillPixelBufferFromImage(resisedImage, pixelBuffer: pixelBuffer)
          
          // generate new append status
          appendSucceeded = pixelBufferAdaptor.appendPixelBuffer(
            pixelBuffer,
            withPresentationTime: presentationTime
          )
          
          /**
           *  Destroy the pixel buffer contains
           */
          pixelBufferPointer.destroy()
        } else {
          NSLog("error: Failed to allocate pixel buffer from pool")
        }
        
        /**
         Destroy the pixel buffer pointer from the memory
         */
        pixelBufferPointer.dealloc(1)
      }
    }
    
    return appendSucceeded
  }
  
  /**
   Private method to append image pixels to a pixel buffer
   
   - parameter image:       The image which pixels will be appented
   - parameter pixelBuffer: The pixel buffer (as memory) to which the image pixels will be appended
   */
  private func fillPixelBufferFromImage(image: UIImage, pixelBuffer: CVPixelBufferRef) {
    // lock the buffer memoty so no one can access it during manipulation
    CVPixelBufferLockBaseAddress(pixelBuffer, 0)
    
    // get the pixel data from the address in the memory
    let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
    
    // create a color scheme
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    
    // generate a context where the image will be drawn (actually the image is appended to the buffer)
    let context = CGBitmapContextCreate(pixelData, Int(image.size.width), Int(image.size.height), CGImageGetBitsPerComponent(image.CGImage), CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace, CGImageAlphaInfo.PremultipliedFirst.rawValue)
    
    // draw the image inside the context (the actual append)
    CGContextDrawImage(context, CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height), image.CGImage)
    
    
    // This doesn't work with smaller displays like the iPhone 5, 5S, 5C, SE, 4S
    // The rease is that the generated image is to big for correct pixels for bytes could be extracted
    
    //    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
    //    let frameSize = CGSizeMake(CGFloat(CGImageGetWidth(image.CGImage!) / 2), CGFloat(CGImageGetHeight(image.CGImage!) / 2))
    //
    //    CVPixelBufferLockBaseAddress(pixelBuffer, 0)
    //    let data = CVPixelBufferGetBaseAddress(pixelBuffer)
    //    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    //    let context = CGBitmapContextCreate(data, Int(frameSize.width), Int(frameSize.height), CGImageGetBitsPerComponent(image.CGImage), CVPixelBufferGetBytesPerRow(pixelBuffer), rgbColorSpace, CGImageAlphaInfo.PremultipliedFirst.rawValue)
    //    CGContextDrawImage(context, CGRectMake(0, 0, CGFloat(CGImageGetWidth(image.CGImage!)), CGFloat(CGImageGetHeight(image.CGImage!))), image.CGImage!)
    
    // unlock the buffer memory
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0)
  }
}
