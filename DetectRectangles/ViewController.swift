//
//  ViewController.swift
//  DetectRectangles
//
//  Created by Bellergy on 21/9/2019.
//  Copyright © 2019 Design Quest Limited. All rights reserved.
//

import UIKit
import AVFoundation
import Vision

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    
    var session = AVCaptureSession()
    var requests = [VNRequest]()
    var capteredBuffer:CVImageBuffer? // current captured video buffer
    
    // MARK: - Config
    
    var sessionPreset = AVCaptureSession.Preset.high // change the capture quality here
    var maximumObservations = 1 // Allows Vision algorithms to return the number of observations.
    var minimumSize:Float = 0.1 // the minimum size of the rectangle to be detected (0 - 1)
    
    // MARK - Outlets
    
    @IBOutlet weak var videoImageView: UIImageView!
    @IBOutlet weak var infoView: UIView!
    @IBOutlet weak var previewImageView: UIImageView!
    
    // MARK: - Override
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startLiveVideo()
        startDetection()
    }
    
    // MARK: - Video session
    
    private func startLiveVideo() {
        if (!session.isRunning) {
            session.sessionPreset = self.sessionPreset
            let captureDevice = AVCaptureDevice.default(for: AVMediaType.video)
            let deviceInput = try! AVCaptureDeviceInput(device: captureDevice!)
            session.addInput(deviceInput)

            let deviceOutput = AVCaptureVideoDataOutput()
            deviceOutput.setSampleBufferDelegate(self, queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
            deviceOutput.videoSettings = [
                String(kCVPixelBufferPixelFormatTypeKey):
                NSNumber(value: kCVPixelFormatType_32BGRA)
            ]
            session.addOutput(deviceOutput)
            
            let videoLayer = AVCaptureVideoPreviewLayer(session: session)
            videoLayer.frame = videoImageView.bounds
            videoImageView.layer.addSublayer(videoLayer)
            
            session.startRunning()
        }
    }
    
    // MARK: - Delegate
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        self.capteredBuffer = pixelBuffer

        var requestOptions:[VNImageOption : Any] = [:]
        if let camData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil) {
            requestOptions = [.cameraIntrinsics:camData]
        }
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation.right, options: requestOptions)
        
        do {
            try imageRequestHandler.perform(self.requests) // pass the analysis requests here
        } catch {
            print(error)
        }
    }
    
    // MARK: - Detection
    
    private func startDetection() {
        let request = VNDetectRectanglesRequest(completionHandler: self.detectionHandler)
        request.maximumObservations = self.maximumObservations
        request.minimumSize = self.minimumSize
        self.requests = [request]
    }
    
    private func detectionHandler(request: VNRequest, error: Error?) {
        guard let results = request.results else { return }
        let observations = results.map({$0 as! VNRectangleObservation})

        DispatchQueue.main.async() {
            let frame = self.infoView.bounds
            
            // Remove all layers
            self.infoView.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
            
            for ob in observations {
                
                if (ob.confidence == 1) {
                    // Fill the detected area
                    let layer = self.drawFrame(observation: ob, frame: frame)
                    self.infoView.layer.addSublayer(layer)
                    
                    // Draw the bounding box
                    let rect = self.scaleBoundingBox(boundingBox: ob.boundingBox, targetFrame: frame)
                    let borderLayer = CALayer()
                    borderLayer.frame = rect
                    borderLayer.borderColor = UIColor.red.cgColor
                    borderLayer.borderWidth = 5
                    self.infoView.layer.addSublayer(borderLayer)
                    
                    // Crop the dected area
                    guard let capteredBuffer = self.capteredBuffer else { break }
                    let ciImage = CIImage(cvPixelBuffer: capteredBuffer)
                        .oriented(forExifOrientation: Int32(CGImagePropertyOrientation.right.rawValue))
                    let imageSize = ciImage.extent.size
                    let boundingBox = ob.boundingBox.scaled(to: imageSize)
                    let topLeft = ob.topLeft.scaled(to: imageSize)
                    let topRight = ob.topRight.scaled(to: imageSize)
                    let bottomLeft = ob.bottomLeft.scaled(to: imageSize)
                    let bottomRight = ob.bottomRight.scaled(to: imageSize)
                    let correctedImage = ciImage
                        .cropped(to: boundingBox)
                        .applyingFilter("CIPerspectiveCorrection", parameters: [
                            "inputTopLeft": CIVector(cgPoint: topLeft),
                            "inputTopRight": CIVector(cgPoint: topRight),
                            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                            "inputBottomRight": CIVector(cgPoint: bottomRight)
                        ])
                        .applyingFilter("CIColorControls", parameters: [
                            kCIInputSaturationKey: 0,
                            kCIInputContrastKey: 32
                        ])
                        .applyingFilter("CIColorInvert")
                    
                    // Show the dected area for preview
                    let image = UIImage(ciImage: correctedImage)
                    self.previewImageView.image = image
                }
            }
            
        }
    }
    
    private func drawFrame(observation ov:VNRectangleObservation, frame: CGRect) -> CAShapeLayer {
        let rectangle = UIBezierPath()
        rectangle.move(to: CGPoint(x: frame.width  * ov.topLeft.x, y: frame.height * (1-ov.topLeft.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.topRight.x, y: frame.height * (1-ov.topRight.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.bottomRight.x, y: frame.height * (1-ov.bottomRight.y)))
        rectangle.addLine(to: CGPoint(x: frame.width * ov.bottomLeft.x, y: frame.height * (1-ov.bottomLeft.y)))
        rectangle.close()
        let rec = CAShapeLayer()
        rec.path = rectangle.cgPath
        rec.fillColor = UIColor.red.cgColor
        rec.borderColor = UIColor.red.cgColor
        rec.opacity = 0.3
        return rec
    }
    
    // Scale boundingBox to target frame
    private func scaleBoundingBox(boundingBox:CGRect, targetFrame: CGRect) -> CGRect {
        let width = CGFloat(targetFrame.width)
        let height = CGFloat(targetFrame.height)
        let rect = CGRect(
            x: width * boundingBox.origin.x,
            y: height * (1 - boundingBox.origin.y - boundingBox.height),
            width: width * boundingBox.width,
            height: height * boundingBox.height)
        return rect
    }
    

}
